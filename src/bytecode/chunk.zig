const std = @import("std");

const OpCode = @import("opcodes.zig").OpCode;

pub const Chunk = struct {
    ops: []OpCode,

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        allocator.free(self.ops);
    }
};

pub const ChunkBuilder = struct {
    const Self = @This();

    ops: std.ArrayList(OpCode),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .ops = std.ArrayList(OpCode).init(allocator),
        };
    }

    pub fn addOp(self: *Self, op: OpCode) !void {
        try self.ops.append(op);
    }

    pub fn build(self: *Self) !Chunk {
        return .{
            .ops = try self.ops.toOwnedSlice(),
        };
    }
};
