const std = @import("std");

const Stmt = @import("statement.zig").Stmt;

pub const BasicBlock = struct {
    statements: []Stmt,
    terminator: ?Stmt,
    label: ?[]const u8,

    pub fn deinit(self: *BasicBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.statements);
    }
};

pub const BasicBlockBuilder = struct {
    const Self = @This();

    statements: std.ArrayList(Stmt),
    terminator: ?Stmt,
    label: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .statements = std.ArrayList(Stmt).init(allocator),
            .terminator = null,
            .label = null,
        };
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

