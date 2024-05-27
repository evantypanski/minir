//! Manages passes that operate on a Program. The Program is modified in
//! place, if at all. This slightly simplifies the interface for running
//! optimizations and other passes.

const std = @import("std");

const Allocator = std.mem.Allocator;

const Function = @import("../../nodes/decl.zig").Function;
const FunctionBuilder = @import("../../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../../nodes/decl.zig").Decl;
const BasicBlock = @import("../../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../../nodes/statement.zig").Stmt;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../../nodes/program.zig").Program;
const Diagnostics = @import("../../diagnostics_engine.zig").Diagnostics;

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

        // Special case: Let pass be void. If so, don't deinit. EVERYTHING else should have deinit
        // This could probably be done better, maybe with a different pass type
        if (@TypeOf(pass) != void) {
            defer pass.deinit();
        }

        // Run dependencies first
        inline for (PassType.dependencies) |dependency| {
            // For now, providers can't be a dependency because we won't do
            // anything with the returned value. If it's necessary in some
            // contexts for it to be a dependency and provide a value in another,
            // maybe the pass should just be split up.
            if (dependency.pass_kind == .provider) {
                @compileError("Providers cannot be a dependency: " ++
                    @typeName(dependency)
                );
            }
            try self.get(dependency);
        }

        var new_pass = PassType {};
        return new_pass.get(&pass, self.program);
    }
};
