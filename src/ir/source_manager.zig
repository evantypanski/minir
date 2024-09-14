const std = @import("std");

const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const Writer = std.fs.File.Writer;

const Program = @import("nodes/program.zig").Program;
const Stmt = @import("nodes/statement.zig").Stmt;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Type = @import("nodes/type.zig").Type;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;
const Loc = @import("sourceloc.zig").Loc;

pub const SourceManager = struct {
    const Self = @This();

    allocator: Allocator,
    source: []const u8,
    filename: ?[]const u8,
    // Indexes for line endings (\n)
    line_ends: []usize,
    owns_source: bool,

    pub fn init(
        allocator: Allocator,
        source: []const u8,
        owns_source: bool
    ) !Self {
        return .{
            .allocator = allocator,
            .source = source,
            .filename = null,
            .line_ends = try analyzeLineEnds(allocator, source),
            .owns_source = owns_source,
        };
    }

    pub fn initFilename(allocator: Allocator, name: []const u8) !Self {
        const file = try std.fs.cwd().openFile(name, .{ .mode = .read_only });
        // TODO: change this limit
        const source = try file.readToEndAlloc(allocator, 10000);
        return .{
            .allocator = allocator,
            .source = source,
            .filename = name,
            .line_ends = try analyzeLineEnds(allocator, source),
            .owns_source = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.owns_source) {
            self.allocator.free(self.source);
        }
        self.allocator.free(self.line_ends);
    }

    fn analyzeLineEnds(
        allocator: Allocator,
        source: []const u8
    ) ![]usize {
        var line_ends = std.ArrayList(usize).init(allocator);
        errdefer line_ends.clearAndFree();
        var i: usize = 0;
        while (i < source.len) : (i += 1) {
            if (source[i] == '\n') {
                try line_ends.append(i);
            }
        }

        return line_ends.toOwnedSlice();
    }

    pub fn getLineNum(self: Self, loc: usize) usize {
        var i: usize = 0;
        while (i < self.line_ends.len) : (i += 1) {
            if (self.line_ends[i] > loc) {
                break;
            }
        }

        return i + 1;
    }

    pub inline fn snip(self: Self, start: usize, end: usize) []const u8 {
        return self.source[start..end];
    }

    pub inline fn get(self: Self, i: usize) u8 {
        return self.source[i];
    }

    pub inline fn len(self: Self) usize {
        return self.source.len;
    }
};
