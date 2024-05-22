const std = @import("std");

const Allocator = std.mem.Allocator;
const Program = @import("../nodes/program.zig").Program;

// TODO: Pass dependencies
pub fn Pass(
    PassTy: type, RetTy: type, dependencies_: []const type,
    init_: *const fn (args: anytype) PassTy,
    run: *const fn (self: *PassTy, program: *Program) RetTy,
) type {
    return struct {
        const Self = @This();

        const execute: *const fn (self: *PassTy, program: *Program) RetTy = run;
        pub const init: *const fn (args: anytype) PassTy = init_;
        pub const dependencies: []const type = dependencies_;
        pub const RetType: type = RetTy;

        result: ?RetTy = null,

        pub fn get(self: *Self, pass: *PassTy, program: *Program) RetTy {
            if (self.result) |res| {
                return res;
            }

            self.result = pass.execute(program);
            return self.result.?;
        }
    };
}
