//! Manages passes that operate on a Program. The Program is modified in
//! place, if at all. This slightly simplifies the interface for running
//! optimizations and other passes.

const std = @import("std");

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const Value = @import("../nodes/value.zig").Value;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;

pub const PassManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    program: *Program,

    pub fn init(allocator: std.mem.Allocator, program: *Program) Self {
        return Self {
            .allocator = allocator,
            .program = program,
        };
    }

    pub fn run(self: Self, comptime PassType: type) !void {
        var pass = PassType.init(self.allocator);
        try pass.execute(self.program);
    }
};
