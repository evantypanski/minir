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

pub const Branch = struct {
    dest_label: []const u8,
    // dest_index will be set from 0 to the actual value when building the
    // function.
    dest_index: usize,
    expr: ?Value,

    pub fn initJump(to: []const u8) Branch {
        return .{
            .dest_label = to, .dest_index = 0, .expr = null
        };
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
            .branch => |*br| {
                if (br.expr) |*val| {
                    val.deinit(allocator);
                }
            },
            else => {},
        }
    }
};
