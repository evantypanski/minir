//! Manages passes that operate on a Program. The Program is modified in
//! place, if at all. This slightly simplifies the interface for running
//! optimizations and other passes.

const std = @import("std");

const Allocator = std.mem.Allocator;

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;

pub const PassManager = struct {
    const Self = @This();

    allocator: Allocator,
    program: *Program,
    diag: Diagnostics,

    pub fn init(
        allocator: Allocator,
        program: *Program,
        diag: Diagnostics
    ) Self {
        return Self {
            .allocator = allocator,
            .program = program,
            .diag = diag,
        };
    }

    /// Gets the result of a given pass type eagerly
    pub fn get(self: Self, comptime PassType: type) PassType.RetType {
        const args = .{
            .allocator = self.allocator,
            .diag = self.diag,
        };
        var pass = PassType.init(args);
        defer pass.deinit();

        // Run dependencies, right now we just run them dumb
        inline for (PassType.dependencies) |dependency| {
            try self.get(dependency);
        }

        var new_pass = PassType {};
        return new_pass.get(&pass, self.program);
    }
};
