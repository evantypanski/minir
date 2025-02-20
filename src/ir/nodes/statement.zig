const std = @import("std");

const Allocator = std.mem.Allocator;

const Value = @import("value.zig").Value;
const Type = @import("type.zig").Type;
const Loc = @import("../sourceloc.zig").Loc;

const StmtTag = enum {
    id,
    branch,
    ret,
    value,
    unreachable_,
};

pub const VarDecl = struct {
    name: []const u8,
    // Initial decl
    val: ?Value,
    ty: ?Type,

    pub fn deinit(self: *VarDecl, allocator: Allocator) void {
        if (self.val) |*val| {
            val.deinit(allocator);
        }
        if (self.ty) |*ty| {
            ty.deinit(allocator);
        }
    }
};

pub const Branch = struct {
    dest_label: []const u8,
    // dest_index will be set from 0 to the actual value when building the
    // function.
    dest_index: usize,
    expr: ?Value,

    pub fn initJump(to: []const u8) Branch {
        return .{ .dest_label = to, .dest_index = 0, .expr = null };
    }

    pub fn initConditional(to: []const u8, value: Value) Branch {
        return .{
            .dest_label = to,
            .dest_index = 0,
            .expr = value,
        };
    }

    pub fn labelName(self: Branch) []const u8 {
        return self.dest_label;
    }
};

pub const StmtKind = union(StmtTag) {
    id: VarDecl,
    branch: Branch,
    ret: ?Value,
    value: Value,
    unreachable_: void,
};

pub const Stmt = struct {
    stmt_kind: StmtKind,
    label: ?[]const u8,
    loc: Loc,

    pub fn init(kind: StmtKind, label: ?[]const u8, loc: Loc) Stmt {
        return .{ .stmt_kind = kind, .label = label, .loc = loc };
    }

    pub fn isTerminator(self: Stmt) bool {
        switch (self.stmt_kind) {
            .id, .value => return false,
            .branch, .ret, .unreachable_ => return true,
        }
    }

    pub fn getLabel(self: Stmt) ?[]const u8 {
        return self.label;
    }

    pub fn deinit(self: *Stmt, allocator: Allocator) void {
        switch (self.*.stmt_kind) {
            .ret => |*ret| {
                if (ret.*) |*val| {
                    val.deinit(allocator);
                }
            },
            .value => |*val| val.deinit(allocator),
            .branch => |*br| {
                if (br.expr) |*val| {
                    val.deinit(allocator);
                }
            },
            .id => |*vd| vd.deinit(allocator),
            .unreachable_ => {},
        }
    }
};
