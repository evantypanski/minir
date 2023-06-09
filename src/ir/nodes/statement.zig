const std = @import("std");

const Value = @import("value.zig").Value;
const Type = @import("type.zig").Type;
const Loc = @import("../sourceloc.zig").Loc;

const StmtTag = enum {
    debug,
    id,
    branch,
    ret,
    value,
};

pub const VarDecl = struct {
    name: []const u8,
    // Initial decl
    val: ?Value,
    ty: ?Type,
};

pub const Jump = struct {
    dest_label: []const u8,
    // dest_index will be set from 0 to the actual value when building the
    // function.
    dest_index: usize,
};

// Should only be created through Branch init instructions so that fields are
// properly set.
pub const ConditionalBranch = struct {
    pub const Kind = enum {
        zero,
        eq,
        less,
        less_eq,
        greater,
        greater_eq,
    };

    kind: Kind,
    success: []const u8,
    lhs: Value,
    rhs: ?Value,

    // dest_index will be set from 0 to the actual value when building the
    // function.
    dest_index: usize,
};

pub const BranchKind = enum {
    jump,
    conditional,
};

pub const Branch = union(BranchKind) {
    // Unconditional is just the label it goes to
    jump: Jump,
    conditional: ConditionalBranch,

    pub fn initJump(to: []const u8) Branch {
        return .{
            .jump = .{ .dest_label = to, .dest_index = 0 },
        };
    }

    pub fn initIfZero(to: []const u8, value: Value) Branch {
        return .{
            .conditional = .{
                .kind = .zero,
                .success = to,
                .lhs = value,
                .rhs = null,
                .dest_index = 0,
            },
        };
    }

    pub fn initBinaryConditional(to: []const u8, kind: ConditionalBranch.Kind,
                                 lhs: Value, rhs: Value) Branch {
        return .{
            .conditional = .{
                .kind = kind,
                .success = to,
                .lhs = lhs,
                .rhs = rhs,
                .dest_index = 0,
            },
        };
    }

    pub fn labelName(self: Branch) []const u8 {
        switch (self) {
            .jump => |j| return j.dest_label,
            .conditional => |conditional| return conditional.success,
        }
    }

    pub fn labelIndex(self: Branch) usize {
        switch (self) {
            .jump => |j| return j.dest_index,
            .conditional => |conditional| return conditional.dest_index,
        }
    }

    pub fn setIndex(self: *Branch, index: usize) void {
        switch (self.*) {
            .jump => |*j| j.dest_index = index,
            .conditional => |*conditional| conditional.dest_index = index,
        }
    }

};

pub const StmtKind = union(StmtTag) {
    debug: Value,
    id: VarDecl,
    branch: Branch,
    ret: ?Value,
    value: Value,
};

pub const Stmt = struct {
    stmt_kind: StmtKind,
    label: ?[]const u8,
    loc: Loc,

    pub fn init(kind: StmtKind, label: ?[]const u8, loc: Loc) Stmt {
        return .{
            .stmt_kind = kind,
            .label = label,
            .loc = loc
        };
    }

    pub fn isTerminator(self: Stmt) bool {
        switch (self.stmt_kind) {
            .debug, .id, .value => return false,
            .branch, .ret => return true,
        }
    }

    pub fn deinit(self: *Stmt, allocator: std.mem.Allocator) void {
        switch (self.*.stmt_kind) {
            .debug => |*val| val.deinit(allocator),
            .ret => |*ret| {
                if (ret.*) |*val| {
                    val.deinit(allocator);
                }
            },
            .value => |*val| val.deinit(allocator),
            else => {},
        }
    }
};
