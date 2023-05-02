const ir = @import("../ir.zig");
const IrVisitor = @import("visitor.zig").IrVisitor;
const std = @import("std");

const Self = @This();
const VisitorTy = IrVisitor(*Self);

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
    .visitVarAccess = visitVarAccess,
};

pub fn visitFunction(self: VisitorTy, arg: *Self, function: *ir.Function) void {
    // This will be uncommented when frames are done
    //arg.num_vars = 0;
    self.walkFunction(arg, function);
}

fn visitVarAccess(self: VisitorTy, arg: *Self, va: *ir.Value.VarAccess) void {
    // This will not remove the name
    va.name = null;
    // This will not increase this when decls are done and map is used
    va.offset = arg.num_vars;
    arg.num_vars += 1;
    _ = self;
}
