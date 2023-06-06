const std = @import("std");
const fmt = std.fmt;
const ArrayList = std.ArrayList;
const Writer = std.fs.File.Writer;

const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig").Value;
const OpCode = @import("opcodes.zig").OpCode;
const errors = @import("errors.zig");

const InterpreterError = errors.RuntimeError || errors.InvalidBytecodeError || Writer.Error;

pub const array_size = 256;

const Frame = struct {
    frame_stack_begin: usize,
    return_pc: usize,
};

pub const Interpreter = struct {
    const Self = @This();

    writer: Writer,
    chunk: Chunk,

    // We have a max function call depth
    call_stack: [array_size]Frame,
    // Index into the call stack of the current function. 1 is main, 0 is
    // reserved to mean no function.
    call_idx: usize,

    stack: [array_size]Value,
    sp: usize,

    // Index into the chunk's instructions. Eventually needs to be a stack
    // with calls
    pc: usize,

    pub fn init(chunk: Chunk, writer: Writer) Self {
        return .{
            .writer = writer,
            .call_stack = [_] Frame { .{
                    .frame_stack_begin = 0,
                    .return_pc = 0
                }} ** array_size,
            .call_idx = 1,
            .chunk = chunk,
            .stack = [_]Value{.undef} ** array_size,
            .sp = 0,
            .pc = 0,
        };
    }

    pub fn interpret(self: *Self) InterpreterError!void {
        // No implicit returns, if we fall off the end then it's an error
        while (self.call_idx != 0) {
            if (self.pc >= self.chunk.bytes.len) {
                return error.ReachedEndNoReturn;
            }

            const op = @intToEnum(OpCode, self.chunk.bytes[self.pc]);
            try self.interpretOp(op);
            // Operators that update the PC should not increment after.
            if (!op.updatesPC()) {
                self.pc += 1;
            }
        }
    }

    pub fn interpretOp(self: *Self, op: OpCode) InterpreterError!void {
        switch (op) {
            .ret => self.pc = try self.popFrame(),
            .constant => try self.pushImmediate(),
            .debug => {
                const value = try self.popVal();
                try self.printValue(value);
            },
            .add, .sub, .mul, .div => {
                const rhs = try self.popVal();
                var lhs = try self.peekVal();

                // Just to reuse code we have another switch to get the op
                // TODO: Maybe make this not pop the LHS and just modify that
                // Value?
                switch (op) {
                    .add => try lhs.add(rhs),
                    .sub => try lhs.sub(rhs),
                    .mul => try lhs.mul(rhs),
                    .div => try lhs.div(rhs),
                    else => unreachable,
                }
            },
            .eq, .ne, .gt, .ge, .lt, .le => {
                // These don't replace the value since they change the type.
                const rhs = try self.popVal();
                const lhs = try self.popVal();

                const result = switch (op) {
                    .eq => try lhs.eq(rhs),
                    .ne => try lhs.ne(rhs),
                    .gt => try lhs.gt(rhs),
                    .ge => try lhs.ge(rhs),
                    .lt => try lhs.lt(rhs),
                    .le => try lhs.lt(rhs),
                    else => unreachable,
                };

                try self.pushValue(result);
            },
            .alloc => self.sp += 1,
            .set => {
                const new_val = try self.popVal();
                const offset = try self.getByte();
                var lhs = try self.getVar(offset);
                lhs.* = new_val;
            },
            .get => {
                // TODO: Maybe this should point to the same Value so we can update it
                // without separate set?
                const offset = try self.getSignedByte();
                try self.pushValue((try self.getVar(offset)).*);
            },
            .jmpf => {
                const condition = try self.popVal();
                const offset = try self.getShort();
                if (!(try condition.asBool())) {
                    self.pc = @intCast(usize, @intCast(isize, self.pc) + offset);
                }
            },
            .call => {
                const absolute = try self.getUnsignedShort();
                try self.pushFrame();
                self.pc = absolute;
            },
        }
    }

    fn pushImmediate(self: *Self) InterpreterError!void {
        const value = try self.getValue(try self.getByte());
        try self.pushValue(value);
    }

    fn pushValue(self: *Self, value: Value) InterpreterError!void {
        if (self.sp >= array_size) {
            return error.StackOverflow;
        }

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

    // Peeks the value and returns a pointer so you can modify it in place
    fn peekVal(self: *Self) InterpreterError!*Value {
        if (self.sp == 0) {
            return error.StackUnderflow;
        }

        return &self.stack[self.sp - 1];
    }

    fn pushFrame(self: *Self) InterpreterError!void {
        if (self.call_idx + 1 >= array_size) {
            return error.MaxFunctionDepth;
        }

        self.call_idx += 1;
        self.call_stack[self.call_idx].frame_stack_begin = self.sp;
        self.call_stack[self.call_idx].return_pc = self.pc + 1;
    }

    // Pops a call frame and returns the PC we should resume at.
    fn popFrame(self: *Self) InterpreterError!usize {
        if (self.call_idx == 0) {
            return error.ReturnWithoutFunction;
        }
        if (self.call_idx >= array_size) {
            return error.MaxFunctionDepth;
        }
        const new_pc = self.call_stack[self.call_idx].return_pc;
        self.call_idx -= 1;
        return new_pc;
    }

    // Returns the top frame in the stack if it exists
    fn peekFrame(self: *Self) ?Frame {
        if (self.call_idx == 0) {
            return null;
        }

        return self.call_stack[self.call_idx];
    }

    // Gets the next byte and increments the index, returning an error if
    // we are off the end.
    fn getByte(self: *Self) InterpreterError!u8 {
        if (self.pc + 1 >= self.chunk.bytes.len) {
            return error.UnexpectedEnd;
        }

        self.pc += 1;
        return self.chunk.bytes[self.pc];
    }

    // Gets the next byte as a signed byte
    fn getSignedByte(self: *Self) InterpreterError!i8 {
        const byte = try self.getByte();
        return @bitCast(i8, byte);
    }


    // Gets the next two bytes as a signed short (i16)
    fn getShort(self: *Self) InterpreterError!i16 {
        if (self.pc + 2 >= self.chunk.bytes.len) {
            return error.UnexpectedEnd;
        }

        self.pc += 2;
        const b1 = self.chunk.bytes[self.pc - 1];
        const b2 = self.chunk.bytes[self.pc];
        return @bitCast(i16, (@intCast(u16, b1) << 8) | @intCast(u16, b2));
    }

    // Gets the next two bytes as an unsigned short (u16)
    fn getUnsignedShort(self: *Self) InterpreterError!u16 {
        if (self.pc + 2 >= self.chunk.bytes.len) {
            return error.UnexpectedEnd;
        }

        self.pc += 2;
        const b1 = self.chunk.bytes[self.pc - 1];
        const b2 = self.chunk.bytes[self.pc];
        return (@intCast(u16, b1) << 8) | @intCast(u16, b2);
    }

    // Gets a value at the specified index, returning an error if it's invalid.
    fn getValue(self: *Self, valueIdx: usize) InterpreterError!Value {
        if (valueIdx >= self.chunk.values.len) {
            return error.InvalidValueIndex;
        }

        return self.chunk.values[valueIdx];
    }

    // Gets a pointer to the value at offset on stack
    fn getVar(self: *Self, relativeOffset: isize) InterpreterError!*Value {
        if (self.peekFrame()) |frame| {
            const absolute = @intCast(isize, frame.frame_stack_begin)
                    + relativeOffset;
            if (absolute < 0) {
                return error.InvalidStackIndex;
            }
            return &self.stack[@intCast(usize, absolute)];
        }

        return error.NoValidFrame;
    }

    fn printValue(self: *Self, value: Value) InterpreterError!void {
        switch (value) {
            .undef => try self.writer.writeAll("undef"),
            .int => |i| try fmt.formatInt(i, 10, .lower, .{}, self.writer),
            .float => |f| try fmt.formatFloatDecimal(f, .{}, self.writer),
            .boolean => |b| try self.writer.print("{}", .{b}),
        }

        try self.writer.writeAll("\n");
    }
};

test "binary ops" {
    const ChunkBuilder = @import("chunk.zig").ChunkBuilder;
    var builder = ChunkBuilder.init(std.testing.allocator);
    const c1 = try builder.addValue(.{ .int = 1 });
    const c2 = try builder.addValue(.{ .int = 2 });
    const c3 = try builder.addValue(.{ .int = 3 });

    try builder.addOp(.constant);
    try builder.addByte(c1);
    try builder.addOp(.constant);
    try builder.addByte(c2);
    try builder.addOp(.add);
    try builder.addOp(.debug);

    try builder.addOp(.constant);
    try builder.addByte(c2);
    try builder.addOp(.constant);
    try builder.addByte(c3);
    try builder.addOp(.sub);
    try builder.addOp(.debug);

    var chunk = try builder.build();

    var dir = std.testing.tmpDir(.{});
    var file = try dir.dir.createFile("binaryops", .{ .read = true });

    var interpreter = Interpreter.init(chunk, file.writer());
    try interpreter.interpret();

    var buffer = [_]u8 { 0 } ** 10;
    const bytes_read = try file.preadAll(&buffer, 0);

    try std.testing.expectEqual(bytes_read, 5);
    // Do starts with so we don't need to deal with EOF stuff
    try std.testing.expectStringStartsWith(&buffer, "3\n-1\n");

    chunk.deinit(std.testing.allocator);
}
