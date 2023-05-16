const std = @import("std");

const Instr = @import("instruction.zig").Instr;

pub const BasicBlock = struct {
    instructions: []Instr,
    terminator: ?Instr,
    label: ?[]const u8,

    pub fn deinit(self: *BasicBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.instructions);
    }
};

pub const BasicBlockBuilder = struct {
    const Self = @This();

    instructions: std.ArrayList(Instr),
    terminator: ?Instr,
    label: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .instructions = std.ArrayList(Instr).init(allocator),
            .terminator = null,
            .label = null,
        };
    }

    pub fn addInstruction(self: *Self, instr: Instr) !void {
        if (instr.isTerminator()) {
            return error.UnexpectedTerminator;
        }
        try self.instructions.append(instr);
    }

    pub fn setTerminator(self: *Self, term: Instr) !void {
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
            .instructions = try self.instructions.toOwnedSlice(),
            .terminator = self.terminator,
            .label = self.label,
        };
    }
};

