const std = @import("std");
const Writer = std.fs.File.Writer;

const Program = @import("../nodes/program.zig").Program;

const JSONError = Writer.Error;

pub const JSONifier = struct {
    writer: Writer,
    program: Program,

    pub fn disassemble(self: JSONifier) JSONError!void {
        try std.json.stringify(self.program, .{}, self.writer);
    }
};
