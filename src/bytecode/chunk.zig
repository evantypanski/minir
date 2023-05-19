const std = @import("std");

const OpCode = @import("opcodes.zig").OpCode;
const Value = @import("value.zig").Value;

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

    pub fn addValue(self: *Self, value: Value) !void {
        try self.values.append(value);
    }

    pub fn build(self: *Self) !Chunk {
        return .{
            .bytes = try self.bytes.toOwnedSlice(),
            .values = try self.values.toOwnedSlice(),
        };
    }
};
