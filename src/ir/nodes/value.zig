const std = @import("std");

const NodeError = @import("../errors.zig").NodeError;
const Token = @import("../token.zig").Token;

const ValueKind = enum {
    undef,
    access,
    int,
    float,
    bool,
    binary,
    call,
};

pub const Value = union(ValueKind) {
    pub const VarAccess = struct {
        name: ?[]const u8,
        offset: ?isize,
    };

    pub const BinaryOp = struct {
        pub const Kind = enum {
            assign,

            eq,
            add,
            sub,
            mul,
            div,

            and_,
            or_,

            lt,
            le,
            gt,
            ge,

            pub fn fromTag(tag: Token.Tag) !Kind {
                // Ignoring float ops for now, those may disappear and you
                // just explicitly cast.
                return switch (tag) {
                    .eq => .assign,
                    .eq_eq => .eq,
                    .plus => .add,
                    .minus => .sub,
                    .star => .mul,
                    .slash => .div,
                    .amp_amp => .and_,
                    .pipe_pipe => .or_,
                    .less => .lt,
                    .less_eq => .le,
                    .greater => .gt,
                    .greater_eq => .ge,
                    else => error.NotAnOperator,
                };
            }
        };

        pub fn deinit(self: *BinaryOp, allocator: std.mem.Allocator) void {
            allocator.destroy(self.lhs);
            allocator.destroy(self.rhs);
        }

        kind: Kind,

        lhs: *Value,
        rhs: *Value,
    };

    pub const FuncCall = struct {
        function: []const u8,
        arguments: []Value,
    };

    undef,
    access: VarAccess,
    int: i32,
    float: f32,
    bool: u1,
    binary: BinaryOp,
    call: FuncCall,

    pub fn initUndef() Value {
        return .undef;
    }

    pub fn initAccessName(name: []const u8) Value {
        return .{ .access = .{ .name = name, .offset = null } };
    }

    pub fn initInt(val: i32) Value {
        return .{
            .int = val,
        };
    }

    pub fn initFloat(f: f32) Value {
        return .{
            .float = f,
        };
    }

    pub fn initBool(val: bool) Value {
        return .{
            .bool = @boolToInt(val),
        };
    }

    pub fn initBinary(kind: BinaryOp.Kind, lhs: *Value, rhs: *Value) Value {
        return .{ .binary = .{
            .kind = kind,
            .lhs = lhs,
            .rhs = rhs,
        } };
    }

    pub fn initCall(function: []const u8, arguments: []Value) Value {
        return .{ .call = .{ .function = function, .arguments = arguments } };
    }

    // Turns a boolean Value into a native boolean. Should not be called
    // on non-bool Values.
    pub fn asBool(self: Value) NodeError!bool {
        switch (self) {
            .bool => |val| return val == 1,
            else => return error.NotABool,
        }
    }

    // Turns an int Value into a native int, else it's not a boolean
    // returns 0.
    pub fn asInt(self: Value) NodeError!i32 {
        switch (self) {
            .int => |val| return val,
            else => return error.NotAnInt,
        }
    }

    // Turns an int Value into a native int, else it's not a boolean
    // returns 0.
    pub fn asFloat(self: Value) NodeError!f32 {
        switch (self) {
            .float => |val| return val,
            else => return error.NotAFloat,
        }
    }

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .binary => |*op| op.deinit(allocator),
            else => {},
        }
    }
};

