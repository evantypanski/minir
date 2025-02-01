const std = @import("std");
const AnyWriter = std.io.AnyWriter;

const Program = @import("../nodes/program.zig").Program;

const JSONError = AnyWriter.Error;

pub const JSONifier = struct {
    writer: AnyWriter,
    program: Program,

    pub fn disassemble(self: JSONifier) JSONError!void {
        try std.json.stringify(self.program, .{}, self.writer);
    }
};
