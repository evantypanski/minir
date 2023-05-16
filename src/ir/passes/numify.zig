const std = @import("std");

const Function = @import("../nodes/function.zig").Function;
const VarDecl = @import("../nodes/instruction.zig").VarDecl;
const Value = @import("../nodes/value.zig").Value;
const IrVisitor = @import("visitor.zig").IrVisitor;

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

pub const NumifyVisitor = VisitorTy {
    .visitFunction = visitFunction,
    .visitVarDecl = visitVarDecl,
    .visitVarAccess = visitVarAccess,
};

pub fn visitFunction(self: VisitorTy, arg: *Self, function: *Function) NumifyError!void {
    arg.map.clearRetainingCapacity();
    arg.num_vars = 0;
    var i: usize = function.params.len;
    for (function.params) |*param| {
        arg.map.put(param.name, -1 * @intCast(isize, i))
                catch return error.MapError;
        i -= 1;
    }
    try self.walkFunction(arg, function);
}

pub fn visitVarDecl(_: VisitorTy, arg: *Self, decl: *VarDecl) NumifyError!void {
    arg.map.put(decl.name, @intCast(isize, arg.num_vars)) catch return error.MapError;
    arg.num_vars += 1;
}

fn visitVarAccess(_: VisitorTy, arg: *Self, va: *Value.VarAccess) NumifyError!void {
    if (va.name) |name| {
        const offset = arg.map.get(name) orelse return error.NoDecl;
        va.offset = offset;
    } else {
        return error.NoName;
    }
}
