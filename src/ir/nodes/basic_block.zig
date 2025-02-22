const std = @import("std");

const Allocator = std.mem.Allocator;

const Stmt = @import("statement.zig").Stmt;

pub const BasicBlock = struct {
    statements: []Stmt,
    terminator: ?Stmt,
    label: ?[]const u8,

    pub fn getLabel(self: BasicBlock) ?[]const u8 {
        return self.label;
    }

    pub fn deinit(self: *BasicBlock, allocator: Allocator) void {
        for (self.statements) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.statements);
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
        };
    }
};
