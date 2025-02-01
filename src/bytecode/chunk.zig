const std = @import("std");

const Allocator = std.mem.Allocator;

const OpCode = @import("opcodes.zig").OpCode;
const Value = @import("value.zig").Value;
const InvalidBytecodeError = @import("errors.zig").InvalidBytecodeError;

pub const ChunkError = error{
    NoHeader,
    InvalidHeader,
};

pub const ChunkHeader = struct {
    // This will change!
    bytes_start: usize,
    const_start: usize,
};

pub const Chunk = struct {
    bytes: []u8,
    values: []Value,

    pub fn deinit(self: *const Chunk, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.values);
    }

    pub fn getHeader(self: Chunk) ChunkHeader {
        return ChunkHeader{
            .bytes_start = @sizeOf(ChunkHeader),
            .const_start = @sizeOf(ChunkHeader) + self.bytes.len,
        };
    }

    pub fn bytesAlloc(self: Chunk, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            std.mem.asBytes(&self.getHeader()),
            self.bytes,
            std.mem.sliceAsBytes(self.values),
        });
    }

    pub fn parse(bytes: []u8, allocator: Allocator) !Chunk {
        if (bytes.len < @sizeOf(ChunkHeader)) {
            return error.NoHeader;
        }

        const header = std.mem.bytesAsValue(ChunkHeader, bytes[0..@sizeOf(ChunkHeader)]);
        if (header.const_start > bytes.len) {
            return error.InvalidHeader;
        }

        const numConstants = (bytes.len - header.const_start) / @sizeOf(Value);

        // Probably should just directly make the slice but oh well for now
        var values = std.ArrayList(Value).init(allocator);
        var pos = header.const_start;
        for (0..numConstants) |_| {
            try values.append(std.mem.bytesAsValue(Value, bytes[pos .. pos + @sizeOf(Value)]).*);
            pos += @sizeOf(Value);
        }

        defer values.clearAndFree();
        const parsed_bytes = bytes[header.bytes_start..header.const_start];

        return Chunk{
            .bytes = try allocator.dupe(u8, parsed_bytes),
            .values = try values.toOwnedSlice(),
        };
    }
};

pub const ChunkBuilder = struct {
    const Self = @This();

    allocator: Allocator,
    bytes: std.ArrayList(u8),
    values: std.ArrayList(Value),

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .bytes = std.ArrayList(u8).init(allocator),
            .values = std.ArrayList(Value).init(allocator),
        };
    }

    /// Invalidates the builder and deinits its memory.
    pub fn deinit(self: *Self) void {
        self.values.clearAndFree();
        self.bytes.clearAndFree();
    }

    // Wrapper for addByte that does the enum cast
    pub fn addOp(self: *Self, op: OpCode) !void {
        try self.addByte(@intFromEnum(op));
    }

    pub fn addByte(self: *Self, byte: u8) !void {
        try self.bytes.append(byte);
    }

    pub fn addShort(self: *Self, short: i16) !void {
        try self.bytes.append(@bitCast(@as(i8, short >> 8)));
        const unsigned_bits: u16 = @bitCast(short);
        try self.bytes.append(@truncate(unsigned_bits));
    }

    // Adds a short and returns the index it was added to. This can then be
    // modified when the absolute address is known.
    pub fn addPlaceholderShort(self: *Self) !usize {
        const placeholder = self.currentByte();
        try self.bytes.append(0);
        try self.bytes.append(0);
        return placeholder;
    }

    pub fn setPlaceholderShort(self: *Self, placeholder: usize, short: u16) !void {
        self.bytes.items[placeholder] =
            @intCast(short >> 8);
        self.bytes.items[placeholder + 1] =
            @intCast(short & 0xFF);
    }

    // Gets the placeholder already at a placeholder. Useful if using it to
    // store a value used later when resolved.
    pub fn getPlaceholderShort(self: *Self, placeholder: usize) u16 {
        return (@as(u16, self.bytes.items[placeholder]) << 8) +
            self.bytes.items[placeholder + 1];
    }

    pub fn addValue(self: *Self, value: Value) !u8 {
        const idx = self.values.items.len;
        if (idx > std.math.maxInt(u8)) {
            return error.TooManyConstants;
        }
        try self.values.append(value);
        return @intCast(idx);
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
