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

const BlockifyError = error{
    AlreadyBlockified,
    MemoryError,
};

pub const BlockifyPass = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, BlockifyError!void);

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub const BlockifyVisitor = VisitorTy {
        .visitDecl = visitDecl,
    };

    pub fn execute(self: *Self, program: *Program) BlockifyError!void {
        try BlockifyVisitor.visitProgram(BlockifyVisitor, self, program);
    }

    pub fn visitDecl(self: VisitorTy, arg: *Self, decl: *Decl) BlockifyError!void {
        _ = self;
        switch (decl.*) {
            .function => |*func| {
                var fn_builder = FunctionBuilder(BasicBlock)
                    .init(arg.allocator, func.name);
                for (func.*.params) |*param| {
                    fn_builder.addParam(param.*) catch return error.MemoryError;
                }
                var bb_builder = BasicBlockBuilder.init(arg.allocator);
                var empty_bb_builder = true;
                for (func.*.elements) |*stmt| {
                    // Labeled statements start a new basic block
                    if (stmt.label) |label| {
                        // Edge case: empty basic blocks shouldn't build
                        if (!empty_bb_builder) {
                            const bb = bb_builder.build()
                                catch return error.MemoryError;
                            fn_builder.addElement(bb)
                                catch return error.MemoryError;
                            bb_builder = BasicBlockBuilder.init(arg.allocator);
                        }
                        bb_builder.setLabel(label);
                        // Remove its label
                        stmt.label = null;
                    }
                    // Even if it has a label, we should go through this in
                    // case that labeled statement is a terminator.
                    if (stmt.isTerminator()) {
                        empty_bb_builder = true;
                        bb_builder.setTerminator(stmt.*)
                            catch return error.MemoryError;
                        const bb = bb_builder.build()
                            catch return error.MemoryError;
                        fn_builder.addElement(bb)
                            catch return error.MemoryError;
                        bb_builder = BasicBlockBuilder.init(arg.allocator);
                    } else {
                        empty_bb_builder = false;
                        bb_builder.addStatement(stmt.*)
                            catch return error.MemoryError;
                    }
                }
                // Maybe there's an implicit return, dunno if I wanna allow that
                if (!empty_bb_builder) {
                    const bb = bb_builder.build() catch return error.MemoryError;
                    fn_builder.addElement(bb) catch return error.MemoryError;
                }
                func.shallowDeinit(arg.allocator);
                decl.* = .{ .bb_function = fn_builder.build() catch unreachable };
            },
            .bb_function => {
                return error.AlreadyBlockified;
            }
        }
    }
};

test "Changes all functions into BB functions" {
    const Loc = @import("../sourceloc.zig").Loc;
    const ProgramBuilder = @import("../nodes/program.zig").ProgramBuilder;
    var func_builder = FunctionBuilder(Stmt).init(std.testing.allocator, "main");
    defer func_builder.deinit();

    try func_builder.addElement(
        Stmt.init(
            .{
                .id = .{
                    .name = "hi",
                    .val = .{ .int = 99 },
                    .ty = .int,
                }
            },
            null,
            Loc.default()
        )
    );
    var hi_access = Value.initAccessName("hi");
    try func_builder.addElement(
        Stmt.init(
            .{ .debug = hi_access },
            null,
            Loc.default()
        )
    );
    // Labeled so new basic block
    try func_builder.addElement(
        Stmt.init(
            .{ .debug = Value.initCall("f", &.{}) },
            "testme",
            Loc.default()
        )
    );

    const func = try func_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addDecl(Decl { .function = func });
    var program = try prog_builder.build();

    // Better way to expect a tagged union value?
    switch (program.decls[0]) {
        .function => |main_func|
            try std.testing.expectEqual(main_func.elements.len, 3),
        .bb_function => try std.testing.expect(false),
    }

    var pass = BlockifyPass.init(std.testing.allocator);
    try pass.execute(&program);

    // Now it should be blockified
    switch (program.decls[0]) {
        .function => try std.testing.expect(false),
        .bb_function => |bb_func|
            try std.testing.expectEqual(bb_func.elements.len, 2),
    }

    program.deinit(std.testing.allocator);
}

// This may not always be necessary, but right now we only act on programs so
// it's all or nothing.
test "Errors when already blockified" {
    const Loc = @import("../sourceloc.zig").Loc;
    const ProgramBuilder = @import("../nodes/program.zig").ProgramBuilder;

    var func_builder = FunctionBuilder(BasicBlock).init(std.testing.allocator, "main");
    defer func_builder.deinit();

    var bb1_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb1_builder.setLabel("bb1");
    try bb1_builder.addStatement(
        Stmt.init(
            .{
                .id = .{
                    .name = "hi",
                    .val = .{ .int = 99 },
                    .ty = .int,
                }
            },
            null,
            Loc.default()
        )
    );
    try func_builder.addElement(try bb1_builder.build());
    const func = try func_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addDecl(Decl { .bb_function = func });
    var program = try prog_builder.build();

    var pass = BlockifyPass.init(std.testing.allocator);
    try std.testing.expectError(error.AlreadyBlockified, pass.execute(&program));

    program.deinit(std.testing.allocator);
}
