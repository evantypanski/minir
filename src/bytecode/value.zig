const RuntimeError = @import("errors.zig").RuntimeError;

pub const ValueKind = enum {
    undef,
    int,
    float,
    boolean,
    ptr,
};

pub const Value = union(ValueKind) {
    const Self = @This();

    undef,
    int: i32,
    float: f32,
    boolean: bool,
    ptr: usize,

    pub fn initUndef() Value {
        return .undef;
    }

    pub fn initInt(i: i32) Value {
        return Self {
            .int = i,
        };
    }

    pub fn initFloat(f: f32) Value {
        return Self {
            .float = f,
        };
    }

    pub fn initBool(b: bool) Value {
        return Self {
            .boolean = b,
        };
    }

    pub fn add(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* += try other.asInt(),
            .float => |*f| f.* += try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        }
    }

    pub fn sub(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* -= try other.asInt(),
            .float => |*f| f.* -= try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        }
    }

    pub fn mul(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* *= try other.asInt(),
            .float => |*f| f.* *= try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        }
    }

    pub fn div(self: *Self, other: Self) RuntimeError!void {
        switch (self.*) {
            .undef => return error.InvalidOperand,
            .int => |*i| i.* = @divTrunc(i.*, try other.asInt()),
            .float => |*f| f.* /= try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        }
    }

    pub fn and_(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => return error.InvalidOperand,
            .float => return error.InvalidOperand,
            .boolean => |b| b and try other.asBool(),
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn or_(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => return error.InvalidOperand,
            .float => return error.InvalidOperand,
            .boolean => |b| b or try other.asBool(),
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn eq(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i == try other.asInt(),
            .float => |f| f == try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn ne(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i != try other.asInt(),
            .float => |f| f != try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn gt(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i > try other.asInt(),
            .float => |f| f > try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn ge(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i >= try other.asInt(),
            .float => |f| f >= try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn lt(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i < try other.asInt(),
            .float => |f| f < try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
    }

    pub fn le(self: Self, other: Self) RuntimeError!Self {
        const result = switch (self) {
            .undef => return error.InvalidOperand,
            .int => |i| i <= try other.asInt(),
            .float => |f| f <= try other.asFloat(),
            .boolean => return error.InvalidOperand,
            .ptr => return error.InvalidOperand,
        };

        return Self.initBool(result);
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

    pub fn asPtr(self: Self) RuntimeError!usize {
        switch (self) {
            .ptr => |to| return to,
            else => return error.ExpectedPtr,
        }
    }
};
