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

    chunk: Chunk,
    writer: Writer,

    // Index into the chunk's instructions
    idx: usize,

    pub fn init(chunk: Chunk, writer: Writer) Self {
        return .{
            .chunk = chunk,
            .writer = writer,
            .idx = 0,
        };
    }

    pub fn disassemble(self: *Self) DisassembleError!void {
        while (self.idx < self.chunk.bytes.len) : (self.idx += 1) {
            const op = @intToEnum(OpCode, self.chunk.bytes[self.idx]);
            self.disassembleOp(op) catch |e| {
                std.log.scoped(.disassembler)
                    .err("Found error while disassembling: {}", .{e});
                // No disassembler errors are fatal
            };
        }
    }

    fn disassembleOp(self: *Self, op: OpCode) DisassembleError!void {
        try self.printAddress();
        switch (op) {
            .ret => try self.writer.writeAll("RET"),
            .constant => {
                try self.writer.writeAll("CONSTANT");
                const immediate = try self.getByte();
                try self.writer.writeAll(" ");
                try self.disassembleValue(try self.getValue(immediate));
            },
            .debug => try self.writer.writeAll("DEBUG"),
            .add => try self.writer.writeAll("ADD"),
            .sub => try self.writer.writeAll("SUB"),
            .mul => try self.writer.writeAll("MUL"),
            .div => try self.writer.writeAll("DIV"),
            .eq => try self.writer.writeAll("EQ"),
            .ne => try self.writer.writeAll("NE"),
            .gt => try self.writer.writeAll("GT"),
            .ge => try self.writer.writeAll("GE"),
            .lt => try self.writer.writeAll("LT"),
            .le => try self.writer.writeAll("LE"),
            .alloc => try self.writer.writeAll("ALLOC"),
            .set => {
                try self.writer.writeAll("SET");
                const immediate = try self.getByte();
                try self.writer.writeAll(" ");
                try self.disassembleOffset(immediate);
            },
            .get => {
                try self.writer.writeAll("GET");
                const immediate = try self.getByte();
                try self.writer.writeAll(" ");
                try self.disassembleOffset(immediate);
            },
            .jmpf => {
                try self.writer.writeAll("JMPF");
                const b1 = try self.getByte();
                const b2 = try self.getByte();
                const relative = @bitCast(i16, (@intCast(u16, b1) << 8) | @intCast(u16, b2));
                try self.writer.print(" {}", .{relative});
            },
            .call => {
                try self.writer.writeAll("CALL ");
                const b1 = try self.getByte();
                const b2 = try self.getByte();
                const absolute = (@intCast(u16, b1) << 8) | @intCast(u16, b2);
                try fmt.formatInt(absolute, 16, .upper, .{.fill = '0', .width = 8 }, self.writer);
            },
        }

        try self.writer.writeAll("\n");
    }

    fn disassembleValue(self: *Self, value: Value) DisassembleError!void {
        switch (value) {
            .undef => try self.writer.writeAll("undef"),
            .int => |i| try fmt.formatInt(i, 10, .lower, .{}, self.writer),
            .float => |f| try fmt.formatFloatDecimal(f, .{}, self.writer),
            .boolean => |b| try self.writer.print("{}", .{b}),
        }
    }

    fn disassembleOffset(self: *Self, offset: u8) DisassembleError!void {
        try self.writer.writeAll("var @fp-");
        try fmt.formatInt(offset, 10, .lower, .{}, self.writer);
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

    fn printAddress(self: *Self) DisassembleError!void {
        try fmt.formatInt(self.idx, 16, .upper, .{.fill = '0', .width = 8 }, self.writer);
        try self.writer.writeAll(": ");
    }
};
