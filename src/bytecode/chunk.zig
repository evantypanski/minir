const std = @import("std");

const OpCode = @import("opcodes.zig").OpCode;
const Value = @import("value.zig").Value;
const InvalidBytecodeError = @import("errors.zig").InvalidBytecodeError;

pub const Chunk = struct {
    bytes: []u8,
    values: []Value,

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.values);
    }
};

pub const ChunkBuilder = struct {
    const Self = @This();

    bytes: std.ArrayList(u8),
    values: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .bytes = std.ArrayList(u8).init(allocator),
            .values = std.ArrayList(Value).init(allocator),
        };
    }

    // Wrapper for addByte that does the enum cast
    pub fn addOp(self: *Self, op: OpCode) !void {
        try self.addByte(@enumToInt(op));
    }

    pub fn addByte(self: *Self, byte: u8) !void {
        try self.bytes.append(byte);
    }

    pub fn addShort(self: *Self, short: i16) !void {
        try self.bytes.append(@bitCast(u8, @intCast(i8, short >> 8)));
        try self.bytes.append(@truncate(u8, @bitCast(u16, short)));
    }

    // Adds a short and returns the index it was added to. This can then be
    // modified when the absolute address is known.
    pub fn addPlaceholderShort(self: *Self) !usize {
        const placeholder = self.currentByte();
        try self.bytes.append(0);
        try self.bytes.append(0);
        return placeholder;
    }

    pub fn setPlaceholderShort(self: *Self, placeholder: usize, short: u16)
            !void {
        self.bytes.items[placeholder] =
            @intCast(u8, short >> 8);
        self.bytes.items[placeholder + 1] =
            @intCast(u8, short & 0xFF);
    }

    pub fn addValue(self: *Self, value: Value) !u8 {
        const idx = self.values.items.len;
        if (idx > std.math.maxInt(u8)) {
            return error.TooManyConstants;
        }
        try self.values.append(value);
        return @intCast(u8, idx);
    }

    // Returns the current length of the chunk, which is where we will append
    // more instructions.
    pub fn currentByte(self: Self) usize {
        return self.bytes.items.len;
    }

    pub fn build(self: *Self) !Chunk {
        return .{
            .bytes = try self.bytes.toOwnedSlice(),
            .values = try self.values.toOwnedSlice(),
        };
    }
};
