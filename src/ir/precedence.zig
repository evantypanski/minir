const std = @import("std");

pub const Precedence = enum(u8) {
    none,
    assign,
    or_,
    and_,
    equal,
    compare,
    term,
    factor,
    unary,
    call,
    primary,

    pub fn gte(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }

    pub fn inc(self: Precedence) Precedence {
        if (self == .primary) {
            return .primary;
        }

        return @enumFromInt(@intFromEnum(self) + 1);
    }
};

