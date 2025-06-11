const std = @import("std");

const Allocator = std.mem.Allocator;

const Modifier = @import("util/pass.zig").Modifier;
const Function = @import("../nodes/decl.zig").Function;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const VarAccess = @import("../nodes/value.zig").VarAccess;
const IrVisitor = @import("util/visitor.zig").IrVisitor;
const Lower = @import("lower.zig").Lower;
const Program = @import("../nodes/program.zig").Program;
const Stmt = @import("../nodes/statement.zig").Stmt;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;

pub const SSA = Modifier(SSAPass, SSAPass.Error, &[_]type{}, SSAPass.init, SSAPass.execute);

pub const SSAPass = struct {
    pub const Error = error{
        MapError,
        NoName,
        NoDecl,
    };

    const Self = @This();
    const VisitorTy = IrVisitor(*Self, Error!void);

    map: std.StringHashMap(isize),
    // Current number of variables in a function
    num_vars: usize,

    pub fn init(args: anytype) Self {
        return .{
            .map = std.StringHashMap(isize).init(args.allocator),
            .num_vars = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.clearAndFree();
    }

    pub const NumifyVisitor = VisitorTy{
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
        .visitVarDecl = visitVarDecl,
        .visitVarAccess = visitVarAccess,
    };

    pub fn execute(self: *Self, program: *Program) Error!void {
        try NumifyVisitor.visitProgram(NumifyVisitor, self, program);
    }

    pub fn visitFunction(visitor: VisitorTy, self: *Self, function: *Function(Stmt)) Error!void {
        try self.handleFnStart(function.params);
        for (function.elements) |*stmt| {
            try visitor.visitStatement(visitor, self, stmt);
        }
    }

    pub fn visitBBFunction(visitor: VisitorTy, self: *Self, function: *Function(BasicBlock)) Error!void {
        try self.handleFnStart(function.params);
        for (function.elements) |*bb| {
            try visitor.visitBasicBlock(visitor, self, bb);
        }
    }

    fn handleFnStart(self: *Self, params: []VarDecl) Error!void {
        self.map.clearRetainingCapacity();
        self.num_vars = 0;
        var i: usize = params.len;
        for (params) |*param| {
            const signed_i: isize = @intCast(i);
            self.map.put(param.name, -1 * signed_i) catch return error.MapError;
            i -= 1;
        }
    }

    pub fn visitVarDecl(_: VisitorTy, self: *Self, decl: *VarDecl) Error!void {
        self.map.put(decl.name, @intCast(self.num_vars)) catch return error.MapError;
        self.num_vars += 1;
    }

    fn visitVarAccess(_: VisitorTy, self: *Self, va: *VarAccess) Error!void {
        if (va.name) |name| {
            const offset = self.map.get(name) orelse return error.NoDecl;
            va.offset = offset;
        } else {
            return error.NoName;
        }
    }
};
