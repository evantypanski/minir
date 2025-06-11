const std = @import("std");

const Allocator = std.mem.Allocator;

const Stmt = @import("statement.zig").Stmt;

pub const BasicBlock = struct {
    statements: []Stmt,
    terminator: ?Stmt,
    label: ?[]const u8,

    previous: std.ArrayList(*BasicBlock),
    next: std.ArrayList(*BasicBlock),

    pub fn getLabel(self: BasicBlock) ?[]const u8 {
        return self.label;
    }

    pub fn addPrevious(self: *BasicBlock, prev: *BasicBlock) !void {
        try self.previous.append(prev);
    }

    pub fn addNext(self: *BasicBlock, next: *BasicBlock) !void {
        try self.next.append(next);
    }

    pub fn jsonStringify(self: BasicBlock, jw: anytype) !void {
        try jw.write(self.statements);
        try jw.write(self.terminator);
        try jw.write(self.label);
        try jw.write(self.previous.items);
        try jw.write(self.next.items);
    }

    pub fn deinit(self: *BasicBlock, allocator: Allocator) void {
        for (self.statements) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.statements);
        self.previous.deinit();
        self.next.deinit();
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
        return .{
            .statements = try self.statements.toOwnedSlice(),
            .terminator = self.terminator,
            .label = self.label,
            .previous = std.ArrayList(*BasicBlock).init(self.allocator),
            .next = std.ArrayList(*BasicBlock).init(self.allocator),
        };
    }
};
