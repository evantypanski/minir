const ir = @import("../ir.zig");
const IrVisitor = @import("visitor.zig").IrVisitor;
const std = @import("std");

const NumifyError = error{
    MapError,
    NoName,
    NoDecl,
};

const Self = @This();
const VisitorTy = IrVisitor(*Self, NumifyError!void);

map: std.StringHashMap(usize),
// Current number of variables in a function
num_vars: usize,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .map = std.StringHashMap(usize).init(allocator),
        .num_vars = 0,
    };
}

pub const NumifyVisitor = VisitorTy {
    .visitFunction = visitFunction,
    .visitVarDecl = visitVarDecl,
    .visitVarAccess = visitVarAccess,
};

pub fn visitFunction(self: VisitorTy, arg: *Self, function: *ir.Function) NumifyError!void {
    arg.num_vars = 0;
    arg.map.clearRetainingCapacity();
    try self.walkFunction(arg, function);
}

pub fn visitVarDecl(_: VisitorTy, arg: *Self, decl: *ir.VarDecl) NumifyError!void {
    arg.map.put(decl.name, arg.num_vars) catch return error.MapError;
    arg.num_vars += 1;
}

fn visitVarAccess(_: VisitorTy, arg: *Self, va: *ir.Value.VarAccess) NumifyError!void {
    if (va.name) |name| {
        const offset = arg.map.get(name) orelse return error.NoDecl;
        va.offset = offset;
    } else {
        return error.NoName;
    }
}
