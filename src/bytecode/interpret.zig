const std = @import("std");
const ArrayList = std.ArrayList;

const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig").Value;

pub const Interpreter = struct {
    const Self = @This();

    env: ArrayList(Value),
    chunk: Chunk,

    pub fn init(allocator: std.mem.Allocator, chunk: Chunk) !Self {
        return .{
            .env = try ArrayList(Value).initCapacity(allocator, 50),
            .chunk = chunk,
        };
    }
};
