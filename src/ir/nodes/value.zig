const std = @import("std");

const Allocator = std.mem.Allocator;

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
        neg,

        pub fn fromTag(tag: Token.Tag) !Kind {
            return switch (tag) {
                .bang => .not,
                .star => .deref,
                .minus => .neg,
                else => error.NotAnOperator,
            };
        }
    };

    kind: Kind,
    val: *Value,

    pub fn deinit(self: *UnaryOp, allocator: Allocator) void {
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

    pub fn deinit(self: *BinaryOp, allocator: Allocator) void {
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
    function: *Value,
    resolved: ?*const Decl,
    arguments: []Value,

    pub fn deinit(self: *FuncCall, allocator: Allocator) void {
        self.function.*.deinit(allocator);
        allocator.destroy(self.function);

        for (self.arguments) |*arg| {
            arg.deinit(allocator);
        }

        allocator.free(self.arguments);
    }

    // For now, function calls can only be var access.
    // TODO: It should have better handling for non-var access cases
    pub fn name(self: FuncCall) []const u8 {
        return self.function.*.val_kind.access.name.?;
    }
};

pub const Pointer = struct {
    to: usize,
    ty: Type,
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
    ptr: Pointer,

    pub fn deinit(self: *ValueKind, allocator: Allocator) void {
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
        function: *Value, arguments: []Value, loc: Loc
    ) Value {
        return .{
            .val_kind = .{
                .call = .{
                    .function = function,
                    .resolved = null,
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

    pub fn initPtr(to: usize, ty: Type, loc: Loc) Value {
        return .{
            .val_kind = .{ .ptr = .{ .to = to, .ty = ty } },
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

    pub fn asPtr(self: Value) NodeError!Pointer {
        switch (self.val_kind) {
            .ptr => |val| return val,
            else => return error.NotAPtr,
        }
    }

    pub fn deinit(self: *Value, allocator: Allocator) void {
        self.*.val_kind.deinit(allocator);
    }
};
