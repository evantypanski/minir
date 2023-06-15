const std = @import("std");
const NodeError = @import("../errors.zig").NodeError;

pub const Type = enum {
    int,
    float,
    boolean,
    // void but avoiding name conflicts is good :)
    none,

    pub fn from_string(str: []const u8) NodeError!Type {
        // This could be better I guess.
        return if (std.mem.eql(u8, str, "int"))
            .int
        else if (std.mem.eql(u8, str, "float"))
            .float
        else if (std.mem.eql(u8, str, "boolean"))
            .boolean
        else if (std.mem.eql(u8, str, "void"))
            .none
        else
            error.InvalidTypeName;
    }
};
