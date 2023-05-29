const RuntimeError = @import("errors.zig").RuntimeError;

pub const ValueKind = enum {
    undef,
    int,
    float,
    boolean,
};

pub const Value = union(ValueKind) {
    const Self = @This();

    undef,
    int: i32,
    float: f32,
    boolean: bool,

    pub fn add(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* += try other.asInt(),
            .float => |*f| f.* += try other.asFloat(),
            .boolean => return error.InvalidOperand,
        }
    }

    pub fn sub(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* -= try other.asInt(),
            .float => |*f| f.* -= try other.asFloat(),
            .boolean => return error.InvalidOperand,
        }
    }

    pub fn mul(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* *= try other.asInt(),
            .float => |*f| f.* *= try other.asFloat(),
            .boolean => return error.InvalidOperand,
        }
    }

    pub fn div(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* = @divTrunc(i.*, try other.asInt()),
            .float => |*f| f.* /= try other.asFloat(),
            .boolean => return error.InvalidOperand,
        }
    }

    pub fn gt(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i > try other.asInt(),
            .float => |f| f > try other.asFloat(),
            .boolean => return error.InvalidOperand,
        };

        return Self { .boolean = result };
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

    pub fn asBool(self: Self) RuntimeError!bool {
        switch (self) {
            .boolean => |b| return b,
            else => return error.ExpectedBool,
        }
    }
};
