const std = @import("std");
const ArrayList = std.ArrayList;

const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig").Value;
const OpCode = @import("opcodes.zig").OpCode;
const errors = @import("errors.zig");

const InterpreterError = errors.RuntimeError || errors.InvalidBytecodeError;

const array_size = 256;

pub const Interpreter = struct {
    const Self = @This();

    chunk: Chunk,

    stack: [array_size]Value,
    sp: usize,

    // Index into the chunk's instructions. Eventually needs to be a stack
    // with calls
    idx: usize,

    pub fn init(chunk: Chunk) Self {
        return .{
            .chunk = chunk,
            .stack = [_]Value{.undef} ** array_size,
            .sp = 0,
            .idx = 0,
        };
    }

    pub fn interpret(self: *Self) InterpreterError!void {
        while (self.idx < self.chunk.bytes.len) : (self.idx += 1) {
            const op = @intToEnum(OpCode, self.chunk.bytes[self.idx]);
            try self.interpretOp(op);
        }
    }

    pub fn interpretOp(self: *Self, op: OpCode) InterpreterError!void {
        switch (op) {
            // TODO ret
            .ret => {},
            .constant => try self.pushVal(),
            .debug => {
                const value = try self.popVal();
                std.debug.print("{}\n", .{value});
            },
        }
    }

    fn pushVal(self: *Self) InterpreterError!void {
        if (self.sp >= array_size) {
            return error.StackOverflow;
        }

        const value = try self.getValue(try self.getByte());
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn popVal(self: *Self) InterpreterError!Value {
        if (self.sp == 0) {
            return error.StackUnderflow;
        }
        self.sp -= 1;
        return self.stack[self.sp];
    }

    // Gets the next byte and increments the index, returning an error if
    // we are off the end.
    fn getByte(self: *Self) InterpreterError!u8 {
        if (self.idx + 1 >= self.chunk.bytes.len) {
            return error.UnexpectedEnd;
        }

        self.idx += 1;
        return self.chunk.bytes[self.idx];
    }

    // Gets a value at the specified index, returning an error if it's invalid.
    fn getValue(self: *Self, valueIdx: usize) InterpreterError!Value {
        if (valueIdx >= self.chunk.values.len) {
            return error.InvalidValueIndex;
        }

        return self.chunk.values[valueIdx];
    }
};
