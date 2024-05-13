const std = @import("std");

const Function = @import("../nodes/decl.zig").Function;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const VarAccess = @import("../nodes/value.zig").VarAccess;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Stmt = @import("../nodes/statement.zig").Stmt;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;

const NumifyError = error{
    MapError,
    NoName,
    NoDecl,
};

const Self = @This();
const VisitorTy = IrVisitor(*Self, NumifyError!void);

map: std.StringHashMap(isize),
// Current number of variables in a function
num_vars: usize,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .map = std.StringHashMap(isize).init(allocator),
        .num_vars = 0,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub const NumifyVisitor = VisitorTy {
    .visitFunction = visitFunction,
    .visitBBFunction = visitBBFunction,
    .visitVarDecl = visitVarDecl,
    .visitVarAccess = visitVarAccess,
};

pub fn execute(self: *Self, program: *Program) NumifyError!void {
    try NumifyVisitor.visitProgram(NumifyVisitor, self, program);
}

pub fn visitFunction(
    visitor: VisitorTy,
    self: *Self,
    function: *Function(Stmt)
) NumifyError!void {
    try self.handleFnStart(function.params);
    try visitor.walkFunction(self, function);
}

pub fn visitBBFunction(
    visitor: VisitorTy,
    self: *Self,
    function: *Function(BasicBlock)
) NumifyError!void {
    try self.handleFnStart(function.params);
    try visitor.walkBBFunction(self, function);
}

fn handleFnStart(self: *Self, params: []VarDecl) NumifyError!void {
    self.map.clearRetainingCapacity();
    self.num_vars = 0;
    var i: usize = params.len;
    for (params) |*param| {
        const signed_i: isize = @intCast(i);
        self.map.put(param.name, -1 * signed_i)
                catch return error.MapError;
        i -= 1;
    }
}

pub fn visitVarDecl(_: VisitorTy, self: *Self, decl: *VarDecl) NumifyError!void {
    self.map.put(decl.name, @intCast(self.num_vars)) catch return error.MapError;
    self.num_vars += 1;
}

fn visitVarAccess(
    _: VisitorTy,
    self: *Self,
    va: *VarAccess
) NumifyError!void {
    if (va.name) |name| {
        const offset = self.map.get(name) orelse return error.NoDecl;
        va.offset = offset;
    } else {
        return error.NoName;
    }
}
