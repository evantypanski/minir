const std = @import("std");

const Allocator = std.mem.Allocator;
const Program = @import("../nodes/program.zig").Program;

pub fn Pass(
    PassTy: type, RetTy: type,
    run: *const fn (self: *PassTy, program: *Program) RetTy
) type {
    return struct {
        const Self = @This();

        const execute: *const fn (self: *PassTy, program: *Program) RetTy = run;
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
