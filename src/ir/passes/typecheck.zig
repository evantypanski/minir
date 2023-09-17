const std = @import("std");

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const Value = @import("../nodes/value.zig").Value;
const VarAccess = @import("../nodes/value.zig").VarAccess;
const Type = @import("../nodes/type.zig").Type;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;
const TypecheckError = @import("../errors.zig").TypecheckError;
const ResolveCallsPass = @import("resolve_calls.zig").ResolveCallsPass;
const Loc = @import("../sourceloc.zig").Loc;

pub const TypecheckPass = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, TypecheckError!void);

    allocator: std.mem.Allocator,
    vars: std.StringHashMap(Type),
    diag: Diagnostics,
    num_errors: usize,

    pub fn init(allocator: std.mem.Allocator, diag: Diagnostics) Self {
        return .{
            .allocator = allocator,
            .vars = std.StringHashMap(Type).init(allocator),
            .diag = diag,
            .num_errors = 0,
        };
    }

    pub const TypecheckVisitor = VisitorTy {
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
        .visitVarDecl = visitVarDecl,
        .visitValue = visitValue,
    };

    pub fn execute(self: *Self, program: *Program) TypecheckError!void {
        // TODO: The resolved calls should be cached somewhere. And this should probably be
        // in the pass manager I guess?
        var resolve_pass = ResolveCallsPass.init(self.allocator, self.diag);
        resolve_pass.execute(program) catch return error.CannotResolve;
        try TypecheckVisitor.visitProgram(TypecheckVisitor, self, program);
        if (self.num_errors > 0) {
            self.diag.diagNumErrors(self.num_errors, "typechecking");
            return error.TooManyErrors;
        }
    }

    pub fn visitFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *Function(Stmt)
    ) TypecheckError!void {
        try self.handleFnStart(function.params);
        try visitor.walkFunction(self, function);
    }

    pub fn visitBBFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *Function(BasicBlock)
    ) TypecheckError!void {
        try self.handleFnStart(function.params);
        try visitor.walkBBFunction(self, function);
    }

    fn handleFnStart(self: *Self, params: []VarDecl) TypecheckError!void {
        self.vars.clearRetainingCapacity();
        for (params) |*param| {
            if (param.ty) |ty| {
                self.vars.put(param.name, ty) catch return error.MapError;
            } else {
                // This could be diagnosed with the diagnostics engine but
                // it really shouldn't happen from the grammar. Maybe fix
                // this.
                return error.ParamWithoutType;
            }
        }
    }

    pub fn visitVarDecl(
        visitor: VisitorTy,
        self: *Self,
        decl: *VarDecl
    ) TypecheckError!void {
        if (decl.*.ty) |ty| {
            self.vars.put(decl.*.name, ty) catch return error.MapError;
        } else if (decl.*.val) |*val| {
            const ty = try self.valTy(val);
            self.vars.put(decl.*.name, ty) catch return error.MapError;
        } else {
            return error.NakedVarDecl;
        }
        try visitor.walkVarDecl(self, decl);
    }

    pub fn visitValue(
        visitor: VisitorTy,
        self: *Self,
        val: *Value
    ) TypecheckError!void {
        // First just grab the type of this value since that may produce
        // diagnostics
        _ = try self.valTy(val);
        // Then do extra work for things we want extra checks on. Diagnostics
        // should only be produced by valTy if it affects the type of the Value,
        // but if it's just an extra check that goes here.
        switch (val.*.val_kind) {
            .call => |*call| {
                // Unfortunately, arity is important to check the arguments,
                // so an arity check has to go here. Alternative is to make this
                // pass depend on another that checks arity, but I haven't made
                // good dependencies between passes yet. We do actually run the
                // resolving pass first though, so we can assume resolved is set.
                const args_len = call.*.arguments.len;
                const decl_params_len = call.*.resolved.?.params().len;
                if (args_len != decl_params_len) {
                    self.num_errors += 1;
                    self.diag.err(
                        error.BadArity,
                        .{ call.*.function, decl_params_len, args_len },
                        val.*.loc
                    );
                }
            },
            else => {},
        }
        try visitor.walkValue(self, val);
    }

    fn valTy(self: *Self, val: *Value) TypecheckError!Type {
        return switch (val.*.val_kind) {
            .undef => .none,
            .access => |*va| self.varAccessTy(va, val.*.loc),
            .int => .int,
            .float => .float,
            .bool => .boolean,
            // For now only unary op is not, but more are planned, so make sure
            // it'll error if more are added
            .unary => |*uo| blk: {
                // Unary ops can only apply to specific types
                switch (uo.*.kind) {
                    .not => {
                        const ty = try self.valTy(uo.*.val);
                        if (!ty.eq(.boolean)) {
                            self.num_errors += 1;
                            self.diag.err(
                                error.InvalidType,
                                .{@tagName(ty), "!"},
                                val.*.loc
                            );
                            break :blk .err;
                        } else {
                            break :blk .boolean;
                        }
                    },
                }
            },
            .binary => |*bo| blk: {
                // All binary ops need both arguments to be of the same type.
                const lhs_ty = try self.valTy(bo.*.lhs);
                const rhs_ty = try self.valTy(bo.*.rhs);
                if (!lhs_ty.eq(rhs_ty)) {
                    self.num_errors += 1;
                    const lhs_loc = bo.*.lhs.loc;
                    const rhs_loc = bo.*.rhs.loc;
                    self.diag.err(
                        error.IncompatibleTypes, .{
                            @tagName(lhs_ty),
                            self.diag.source_mgr.snip(
                                lhs_loc.start,
                                lhs_loc.end
                            ),
                            @tagName(rhs_ty),
                            self.diag.source_mgr.snip(
                                rhs_loc.start,
                                rhs_loc.end
                            ),
                        }, val.*.loc
                    );
                    break :blk .err;
                }

                break :blk switch (bo.*.kind) {
                    .assign, .add, .sub, .mul, .div => lhs_ty,
                    .eq, .and_, .or_, .lt, .le, .gt, .ge => .boolean,
                };
            },
            // Don't check whether params are right here since it won't change
            // the type of this particular expression.
            .call => |call| call.resolved.?.ty(),
        };
    }

    fn varAccessTy(self: *Self, va: *VarAccess, loc: Loc) TypecheckError!Type {
        const name = va.*.name.?;
        return self.*.vars.get(name) orelse blk: {
            self.diag.err(error.Unresolved, .{ name }, loc);
            break :blk .err;
        };
    }
};
