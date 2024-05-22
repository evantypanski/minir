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
        var pass = if (comptime shouldPassDiagToPass(PassType))
            PassType.init(self.allocator, self.diag)
        else
            PassType.init(self.allocator);
        // Make sure we deinit too.
        defer pass.deinit();
        return pass.execute(self.program);
    }

    /// Gets the result of a given pass type through the new Pass interface
    pub fn get(
        self: Self,
        comptime PassType: type,
        comptime Inner: type
    ) PassType.RetType {
        var pass = if (comptime shouldPassDiagToPass(Inner))
            Inner.init(self.allocator, self.diag)
        else
            Inner.init(self.allocator);
        defer pass.deinit();
        var new_pass = PassType {};
        return new_pass.get(&pass, self.program);
    }

    fn passRetTy(comptime PassType: type) type {
        // Is there a better way to do this????
        return @typeInfo(@TypeOf(PassType.execute)).Fn.return_type.?;
    }

    fn shouldPassDiagToPass(comptime PassType: type) bool {
        // Right now we determine if we pass diag by seeing if the init
        // function takes 2 arguments. In the future it may be worth making
        // this a little nicer.
        return @typeInfo(@TypeOf(PassType.init)).Fn.params.len == 2;
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
