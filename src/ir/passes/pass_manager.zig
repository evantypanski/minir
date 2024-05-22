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

    pub fn run(
        self: Self,
        comptime PassType: type
    ) passRetTy(PassType) {
        try self.resolvePassDependencies(PassType);
        const args = .{
            .allocator = self.allocator,
            .diag = self.diag,
        };
        var pass = PassType.init(args);
        // Make sure we deinit too.
        defer pass.deinit();
        return pass.execute(self.program);
    }

    /// Gets the result of a given pass type through the new Pass interface
    pub fn get(
        self: Self,
        comptime PassType: type,
    ) PassType.RetType {
        const args = .{
            .allocator = self.allocator,
            .diag = self.diag,
        };
        var pass = PassType.init(args);
        defer pass.deinit();
        var new_pass = PassType {};
        return new_pass.get(&pass, self.program);
    }

    fn passRetTy(comptime PassType: type) type {
        // Is there a better way to do this????
        return @typeInfo(@TypeOf(PassType.execute)).Fn.return_type.?;
    }

    /// A pass can have a public `dependencies` array that lists the passes
    /// that should run before this one. These cannot return a type other than
    /// the error type, they must provide their result through side effects
    /// in the AST. Since this may still error, whatever pass depends on
    /// each pass must contain all errors from the dependent pass or this will
    /// throw a compile error.
    fn resolvePassDependencies(self: Self, comptime PassType: type) !void {
        if (@hasDecl(PassType, "dependencies")) {
            inline for (PassType.dependencies) |dep| {
                try self.run(dep);
            }
        }
    }
};
