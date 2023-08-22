const std = @import("std");

const NodeError = @import("../errors.zig").NodeError;
const Token = @import("../token.zig").Token;

const ValueKind = enum {
    undef,
    access,
    int,
    float,
    bool,
    unary,
    binary,
    call,
};

pub const Value = union(ValueKind) {
    pub const VarAccess = struct {
        name: ?[]const u8,
        offset: ?isize,
    };

    pub const UnaryOp = struct {
        pub const Kind = enum {
            not,

            pub fn fromTag(tag: Token.Tag) !Kind {
                return switch (tag) {
                    .bang => .not,
                    else => error.NotAnOperator,
                };
            }
        };

        kind: Kind,
        val: *Value,

        pub fn deinit(self: *UnaryOp, allocator: std.mem.Allocator) void {
            self.val.*.deinit(allocator);
            allocator.destroy(self.val);
        }

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
            self.lhs.deinit(allocator);
            allocator.destroy(self.lhs);
            self.rhs.deinit(allocator);
            allocator.destroy(self.rhs);
        }

        kind: Kind,

        lhs: *Value,
        rhs: *Value,
    };

    pub const FuncCall = struct {
        function: []const u8,
        arguments: []Value,

        pub fn deinit(self: *FuncCall, allocator: std.mem.Allocator) void {
            for (self.arguments) |*arg| {
                arg.deinit(allocator);
            }

            allocator.free(self.arguments);
        }
    };

    undef,
    access: VarAccess,
    int: i32,
    float: f32,
    bool: u1,
    unary: UnaryOp,
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
            .bool = @intFromBool(val),
        };
    }

    pub fn initUnary(kind: UnaryOp.Kind, val: *Value) Value {
        return .{ .unary = .{
            .kind = kind,
            .val = val,
        } };
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
            .unary => |*op| op.deinit(allocator),
            .binary => |*op| op.deinit(allocator),
            .call => |*call| call.deinit(allocator),
            else => {},
        }
    }
};

