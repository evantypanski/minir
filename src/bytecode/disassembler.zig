const fmt = @import("std").fmt;
const Writer = @import("std").fs.File.Writer;

const OpCode = @import("opcodes.zig").OpCode;
const Chunk = @import("chunk.zig").Chunk;

pub const Disassembler = struct {
    const Self = @This();

    writer: Writer,
    chunk: Chunk,

    pub fn disassemble(self: Self) Writer.Error!void {
        for (self.chunk.ops) |op| {
            try self.disassembleOp(op);
        }
    }

    fn disassembleOp(self: Self, op: OpCode) Writer.Error!void {
        const str = switch (op) {
            .ret => "RET",
        };

        try self.writer.print("{s}\n", .{str});
    }
};
