const RuntimeError = @import("errors.zig").RuntimeError;

pub const ValueKind = enum {
    undef,
    int,
    float,
};

pub const Value = union(ValueKind) {
    const Self = @This();

    undef,
    int: i32,
    float: f32,

    pub fn add(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* += try other.asInt(),
            .float => |*f| f.* += try other.asFloat(),
        }
    }

    pub fn sub(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* -= try other.asInt(),
            .float => |*f| f.* -= try other.asFloat(),
        }
    }

    pub fn mul(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* *= try other.asInt(),
            .float => |*f| f.* *= try other.asFloat(),
        }
    }

    pub fn div(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* = @divTrunc(i.*, try other.asInt()),
            .float => |*f| f.* /= try other.asFloat(),
        }
    }

    pub fn asInt(self: Self) RuntimeError!i32 {
        switch (self) {
            .int => |i| return i,
            else => return error.ExpectedInt,
        }
    }

    pub fn asFloat(self: Self) RuntimeError!f32 {
        switch (self) {
            .float => |f| return f,
            else => return error.ExpectedFloat,
        }
    }
};
