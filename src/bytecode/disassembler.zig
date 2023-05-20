const std = @import("std");
const fmt = std.fmt;
const Writer = std.fs.File.Writer;

const OpCode = @import("opcodes.zig").OpCode;
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig").Value;
const InvalidBytecodeError = @import("errors.zig").InvalidBytecodeError;

pub const DisassembleError = InvalidBytecodeError || Writer.Error;

pub const Disassembler = struct {
    const Self = @This();

    writer: Writer,
    chunk: Chunk,

    // Index into the chunk's instructions
    idx: usize,

    pub fn init(writer: Writer, chunk: Chunk) Self {
        return .{
            .writer = writer,
            .chunk = chunk,
            .idx = 0,
        };
    }

    pub fn disassemble(self: *Self) DisassembleError!void {
        while (self.idx < self.chunk.bytes.len) : (self.idx += 1) {
            const op = @intToEnum(OpCode, self.chunk.bytes[self.idx]);
            try self.disassembleOp(op);
        }
    }

    fn disassembleOp(self: *Self, op: OpCode) DisassembleError!void {
        const str = switch (op) {
            .ret => "RET",
            .constant => "CONSTANT",
            .debug => "DEBUG",
            .add => "ADD",
            .sub => "SUB",
            .mul => "MUL",
            .div => "DIV",
        };

        try self.writer.print("{s}", .{str});

        // For now anything that pushes to the stack pushes immediate,
        // but this may change and we'll need a separate function.
        // This also applies to the verifier.
        var immediatesLeft = op.numImmediates();
        var first = true;
        while (immediatesLeft > 0) : (immediatesLeft -= 1) {
            if (!first) {
                try self.writer.writeAll(",");
                first = false;
            }
            const valueIdx = try self.getByte();
            try self.writer.writeAll(" ");
            try self.disassembleValue(try self.getValue(valueIdx));
        }

        try self.writer.writeAll("\n");
    }

    fn disassembleValue(self: *Self, value: Value) DisassembleError!void {
        switch (value) {
            .undef => try self.writer.writeAll("undef"),
            .int => |i| try fmt.formatInt(i, 10, .lower, .{}, self.writer),
            .float => |f| try fmt.formatFloatDecimal(f, .{}, self.writer),
        }
    }

    // Gets the next byte and increments the index, returning an error if
    // we are off the end.
    fn getByte(self: *Self) DisassembleError!u8 {
        if (self.idx + 1 >= self.chunk.bytes.len) {
            return error.UnexpectedEnd;
        }

        self.idx += 1;
        return self.chunk.bytes[self.idx];
    }

    // Gets a value at the specified index, returning an error if it's invalid.
    fn getValue(self: *Self, valueIdx: usize) DisassembleError!Value {
        if (valueIdx >= self.chunk.values.len) {
            return error.InvalidValueIndex;
        }

        return self.chunk.values[valueIdx];
    }
};
