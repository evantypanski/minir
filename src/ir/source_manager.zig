const std = @import("std");

const fmt = std.fmt;
const Writer = @import("std").fs.File.Writer;

const Program = @import("nodes/program.zig").Program;
const Stmt = @import("nodes/statement.zig").Stmt;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Value = @import("nodes/value.zig").Value;
const Type = @import("nodes/type.zig").Type;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;
const ParseError = @import("errors.zig").ParseError;
const Loc = @import("sourceloc.zig").Loc;

pub const SourceManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    source: []u8,
    filename: []const u8,
    // Indexes for line endings (\n)
    line_ends: []usize,

    pub fn init(
        allocator: std.mem.Allocator,
        source: []u8,
        filename: []const u8
    ) !Self {
        var self = Self {
            .allocator = allocator,
            .source = source,
            .filename = filename,
            .line_ends = try analyzeLineEnds(allocator, source),
        };

        return self;
    }

    pub fn initFilename(allocator: std.mem.Allocator, name: []const u8) !Self {
        const file = try std.fs.cwd().openFile(name, .{ .mode = .read_only });
        return init(allocator, try file.readToEndAlloc(allocator, 10000), name);
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.source);
        self.allocator.free(self.line_ends);
    }

    fn analyzeLineEnds(
        allocator: std.mem.Allocator,
        source: []const u8
    ) ![]usize {
        var line_ends = std.ArrayList(usize).init(allocator);
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

    pub inline fn snip(self: Self, start: usize, end: usize) []u8 {
        return self.source[start..end];
    }

    pub inline fn get(self: Self, i: usize) u8 {
        return self.source[i];
    }

    pub inline fn len(self: Self) usize {
        return self.source.len;
    }
};
