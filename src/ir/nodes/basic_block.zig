const std = @import("std");

const Allocator = std.mem.Allocator;

const Stmt = @import("statement.zig").Stmt;

pub const BasicBlock = struct {
    statements: []Stmt,
    terminator: ?Stmt,
    label: []const u8,

    previous_labels: std.ArrayList([]const u8),
    next_labels: std.ArrayList([]const u8),

    pub fn getLabel(self: BasicBlock) ?[]const u8 {
        return self.label;
    }

    pub fn addPrevious(self: *BasicBlock, prev_label: []const u8) !void {
        try self.previous_labels.append(prev_label);
    }

    pub fn addNext(self: *BasicBlock, next_label: []const u8) !void {
        try self.next_labels.append(next_label);
    }

    pub fn jsonStringify(self: BasicBlock, jw: anytype) !void {
        try jw.write(self.statements);
        try jw.write(self.terminator);
        try jw.write(self.label);
        for (self.previous_labels.items) |prev| {
            try jw.write(prev);
        }
        for (self.next_labels.items) |next| {
            try jw.write(next);
        }
    }

    pub fn deinit(self: *BasicBlock, allocator: Allocator) void {
        for (self.statements) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.statements);
        allocator.free(self.label);
        self.previous_labels.deinit();
        self.next_labels.deinit();
    }
};

pub const BasicBlockBuilder = struct {
    const Self = @This();

    allocator: Allocator,
    statements: std.ArrayList(Stmt),
    terminator: ?Stmt,
    label: ?[]const u8,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .statements = std.ArrayList(Stmt).init(allocator),
            .terminator = null,
            .label = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.statements.clearAndFree();
        if (self.label) |*label| {
            self.allocator.free(label.*);
        }
    }

    pub fn addStatement(self: *Self, stmt: Stmt) !void {
        if (stmt.isTerminator()) {
            return error.UnexpectedTerminator;
        }
        try self.statements.append(stmt);
    }

    pub fn setTerminator(self: *Self, term: Stmt) !void {
        if (!term.isTerminator()) {
            return error.ExpectedTerminator;
        }

        self.terminator = term;
    }

    pub fn setLabel(self: *Self, label: []const u8) void {
        self.label = label;
    }

    pub fn build(self: *Self) !BasicBlock {
        if (self.label == null) return error.ExpectedLabel;
        const label = self.label orelse unreachable;
        self.label = null;
        return .{
            .statements = try self.statements.toOwnedSlice(),
            .terminator = self.terminator,
            .label = label,
            .previous_labels = std.ArrayList([]const u8).init(self.allocator),
            .next_labels = std.ArrayList([]const u8).init(self.allocator),
        };
    }
};
