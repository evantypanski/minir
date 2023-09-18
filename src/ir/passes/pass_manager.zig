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
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;

pub const PassManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    program: *Program,
    diag: Diagnostics,

    pub fn init(
        allocator: std.mem.Allocator,
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
        var pass = if (comptime shouldPassDiagToPass(PassType))
            PassType.init(self.allocator, self.diag)
        else
            PassType.init(self.allocator);
        return pass.execute(self.program);
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
};
