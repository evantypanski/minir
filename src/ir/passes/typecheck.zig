const std = @import("std");

const Allocator = std.mem.Allocator;

const Verifier = @import("util/pass.zig").Verifier;
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
const ConstIrVisitor = @import("util/const_visitor.zig").ConstIrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;
const Loc = @import("../sourceloc.zig").Loc;
const ResolveCalls = @import("resolve_calls.zig").ResolveCalls;
const ResolveCallsPass = @import("resolve_calls.zig").ResolveCallsPass;

pub const Typecheck = Verifier(
    TypecheckPass, TypecheckPass.Error, &[_]type{ResolveCalls},
    TypecheckPass.init, TypecheckPass.execute
);

pub const TypecheckPass = struct {
    pub const Error = error {
        MapError,
        ParamWithoutType,
        TooManyErrors,
        NakedVarDecl,
        CannotEvaluateType,
        Unimplemented,
        IncompatibleTypes,
        CannotResolve,
        InvalidType,
        BadArity,
        Unresolved,
    } || ResolveCallsPass.Error;

    const Self = @This();
    const VisitorTy = ConstIrVisitor(*Self, Error!void);

    allocator: Allocator,
    vars: std.StringHashMap(Type),
    diag: Diagnostics,
    num_errors: usize,
    current_fn: ?*const Decl,

    pub fn init(args: anytype) Self {
        return .{
            .allocator = args.allocator,
            .vars = std.StringHashMap(Type).init(args.allocator),
            .diag = args.diag,
            .num_errors = 0,
            .current_fn = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.vars.deinit();
    }

    pub const TypecheckVisitor = VisitorTy {
        .visitDecl = visitDecl,
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
        .visitVarDecl = visitVarDecl,
        .visitValue = visitValue,
        .visitStatement = visitStatement,
    };

    pub fn execute(self: *Self, program: *const Program) Error!void {
        try TypecheckVisitor.visitProgram(TypecheckVisitor, self, program);
        if (self.num_errors > 0) {
            self.diag.diagNumErrors(self.num_errors, "typechecking");
            return error.TooManyErrors;
        }
    }

    pub fn visitDecl(
        visitor: VisitorTy,
        self: *Self,
        decl: *const Decl
    ) Error!void {
        self.current_fn = decl;
        try visitor.walkDecl(self, decl);
    }

    pub fn visitFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *const Function(Stmt)
    ) Error!void {
        try self.handleFnStart(function.params);
        try visitor.walkFunction(self, function);
    }

    pub fn visitBBFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *const Function(BasicBlock)
    ) Error!void {
        try self.handleFnStart(function.params);
        try visitor.walkBBFunction(self, function);
    }

    fn handleFnStart(self: *Self, params: []VarDecl) Error!void {
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
        decl: *const VarDecl
    ) Error!void {
        if (decl.*.ty) |ty| {
            self.vars.put(decl.*.name, ty) catch return error.MapError;
        } else if (decl.*.val) |*val| {
            const ty = self.valTy(val);
            self.vars.put(decl.*.name, ty) catch return error.MapError;
        } else {
            return error.NakedVarDecl;
        }
        try visitor.walkVarDecl(self, decl);
    }

    pub fn visitValue(
        visitor: VisitorTy,
        self: *Self,
        val: *const Value
    ) Error!void {
        // First just grab the type of this value since that may produce
        // diagnostics
        _ = self.valTy(val);
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
                        .{ call.*.name(), decl_params_len, args_len },
                        val.*.loc
                    );
                }
            },
            else => {},
        }
        try visitor.walkValue(self, val);
    }

    fn valTy(self: *Self, val: *const Value) Type {
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
                const ty = self.valTy(uo.*.val);
                switch (uo.*.kind) {
                    .not => {
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
                    .deref => {
                        // Can only deref pointers
                        switch (ty) {
                            .pointer => |to_ty| break :blk to_ty.*,
                            else => {
                                self.num_errors += 1;
                                self.diag.err(
                                    error.InvalidType,
                                    .{@tagName(ty), "*"},
                                    val.*.loc
                                );
                                break :blk .err;
                            }
                        }
                    },
                    .neg => {
                        // Can only negate int/float
                        switch (ty) {
                            .int, .float => break :blk ty,
                            else => {
                                self.num_errors += 1;
                                self.diag.err(
                                    error.InvalidType,
                                    .{@tagName(ty), "-"},
                                    val.*.loc
                                );
                                break :blk .err;
                            }
                        }
                    }
                }
            },
            .binary => |*bo| blk: {
                // All binary ops need both arguments to be of the same type.
                const lhs_ty = self.valTy(bo.*.lhs);
                const rhs_ty = self.valTy(bo.*.rhs);
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
            .call => |call| blk: {
                break :blk call.resolved.?.ty();
            },
            .type_ => .type_,
            .ptr => |ptr| ptr.ty,
        };
    }

    fn varAccessTy(self: *Self, va: *const VarAccess, loc: Loc) Type {
        const name = va.*.name.?;
        return self.*.vars.get(name) orelse blk: {
            self.diag.err(error.Unresolved, .{ name }, loc);
            break :blk .err;
        };
    }

    pub fn visitStatement(
        visitor: VisitorTy,
        self: *Self,
        stmt: *const Stmt
    ) Error!void {
        switch (stmt.*.stmt_kind) {
            .branch => |*br| {
                if (br.*.expr) |*val| {
                    const ty = self.valTy(val);
                    if (!ty.eq(.boolean)) {
                        self.num_errors += 1;
                        self.diag.err(
                            error.InvalidType,
                            .{@tagName(ty), "brc"},
                            val.*.loc
                        );
                    }
                }
            },
            .ret => |*opt_ret_val| {
                if (opt_ret_val.*) |*ret_val| {
                    const ret_val_ty = self.valTy(ret_val);
                    const fn_ty = self.current_fn.?.*.ty();
                    if (!ret_val_ty.eq(fn_ty)) {
                        self.num_errors += 1;
                        self.diag.err(
                            error.IncompatibleTypes,
                            .{
                                @tagName(ret_val_ty),
                                self.diag.source_mgr.snip(
                                    ret_val.*.loc.start,
                                    ret_val.*.loc.end
                                ),
                                @tagName(fn_ty),
                                self.current_fn.?.*.name(),
                            },
                            stmt.*.loc
                        );
                    }
                }
            },
            else => {},
        }
        try visitor.walkStatement(self, stmt);
    }
};
