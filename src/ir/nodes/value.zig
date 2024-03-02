const std = @import("std");

const NodeError = @import("../errors.zig").NodeError;
const Token = @import("../token.zig").Token;
const Loc = @import("../sourceloc.zig").Loc;
const Decl = @import("decl.zig").Decl;
const Type = @import("type.zig").Type;

const ValueTag = enum {
    undef,
    access,
    int,
    float,
    bool,
    unary,
    binary,
    call,
    type_,
    ptr,
};

pub const VarAccess = struct {
    name: ?[]const u8,
    offset: ?isize,
};

pub const UnaryOp = struct {
    pub const Kind = enum {
        not,
        deref,

        pub fn fromTag(tag: Token.Tag) !Kind {
            return switch (tag) {
                .bang => .not,
                .star => .deref,
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
    resolved: ?*Decl,
    builtin: bool,
    arguments: []Value,

    pub fn deinit(self: *FuncCall, allocator: std.mem.Allocator) void {
        for (self.arguments) |*arg| {
            arg.deinit(allocator);
        }

        allocator.free(self.arguments);
    }
};

pub const ValueKind = union(ValueTag) {
    undef,
    access: VarAccess,
    int: i32,
    float: f32,
    bool: u1,
    unary: UnaryOp,
    binary: BinaryOp,
    call: FuncCall,
    type_: Type,
    ptr: usize,

    pub fn deinit(self: *ValueKind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .unary => |*op| op.deinit(allocator),
            .binary => |*op| op.deinit(allocator),
            .call => |*call| call.deinit(allocator),
            else => {},
        }
    }
};

pub const Value = struct {
    val_kind: ValueKind,
    loc: Loc,

    pub fn initUndef(loc: Loc) Value {
        return .{ .val_kind = .undef, .loc = loc };
    }

    pub fn initAccessName(name: []const u8, loc: Loc) Value {
        return .{
            .val_kind = .{ .access = .{ .name = name, .offset = null } },
            .loc = loc,
        };
    }

    pub fn initInt(val: i32, loc: Loc) Value {
        return .{
            .val_kind = .{ .int = val },
            .loc = loc,
        };
    }

    pub fn initFloat(f: f32, loc: Loc) Value {
        return .{
            .val_kind = .{ .float = f },
            .loc = loc,
        };
    }

    pub fn initBool(val: bool, loc: Loc) Value {
        return .{
            .val_kind = .{ .bool = @intFromBool(val) },
            .loc = loc,
        };
    }

    pub fn initUnary(kind: UnaryOp.Kind, val: *Value, loc: Loc) Value {
        return .{
            .val_kind = .{
                .unary = .{
                    .kind = kind,
                    .val = val,
                }
            },
            .loc = loc,
        };
    }

    pub fn initBinary(
        kind: BinaryOp.Kind, lhs: *Value, rhs: *Value, loc: Loc
    ) Value {
        return .{
            .val_kind = .{
                .binary = .{
                    .kind = kind,
                    .lhs = lhs,
                    .rhs = rhs,
                }
            },
            .loc = loc,
        };
    }

    pub fn initCall(
        function: []const u8, builtin: bool, arguments: []Value, loc: Loc
    ) Value {
        return .{
            .val_kind = .{
                .call = .{
                    .function = function,
                    .resolved = null,
                    .builtin = builtin,
                    .arguments = arguments
                }
            },
            .loc = loc,
        };
    }

    pub fn initType(ty: Type, loc: Loc) Value {
        return .{
            .val_kind = .{ .type_ = ty },
            .loc = loc,
        };
    }

    pub fn initPtr(to: usize, loc: Loc) Value {
        return .{
            .val_kind = .{ .ptr = to },
            .loc = loc,
        };
    }

    // Turns a boolean Value into a native boolean. Should not be called
    // on non-bool Values.
    pub fn asBool(self: Value) NodeError!bool {
        switch (self.val_kind) {
            .bool => |val| return val == 1,
            else => return error.NotABool,
        }
    }

    // Turns an int Value into a native int, else it's not a boolean
    // returns 0.
    pub fn asInt(self: Value) NodeError!i32 {
        switch (self.val_kind) {
            .int => |val| return val,
            else => return error.NotAnInt,
        }
    }

    // Turns an int Value into a native int, else it's not a boolean
    // returns 0.
    pub fn asFloat(self: Value) NodeError!f32 {
        switch (self.val_kind) {
            .float => |val| return val,
            else => return error.NotAFloat,
        }
    }

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        self.*.val_kind.deinit(allocator);
    }
};
