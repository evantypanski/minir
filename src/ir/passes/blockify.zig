const std = @import("std");

const Allocator = std.mem.Allocator;

const Modifier = @import("util/pass.zig").Modifier;
const IrVisitor = @import("util/visitor.zig").IrVisitor;
const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const Value = @import("../nodes/value.zig").Value;
const Program = @import("../nodes/program.zig").Program;
const Loc = @import("../sourceloc.zig").Loc;
const NodeError = @import("../nodes/errors.zig").NodeError;

pub const Blockify = Modifier(BlockifyPass, BlockifyPass.Error, &[_]type{}, BlockifyPass.init, BlockifyPass.execute);

pub const BlockifyPass = struct {
    pub const Error = error{
        AlreadyBlockified,
    } || Allocator.Error || NodeError;

    const Self = @This();
    const VisitorTy = IrVisitor(*Self, Error!void);

    allocator: Allocator,

    pub fn init(args: anytype) Self {
        return .{
            .allocator = args.allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub const BlockifyVisitor = VisitorTy{
        .visitDecl = visitDecl,
    };

    pub fn execute(self: *Self, program: *Program) Error!void {
        try BlockifyVisitor.visitProgram(BlockifyVisitor, self, program);
    }

    pub fn visitDecl(self: VisitorTy, arg: *Self, decl: *Decl) Error!void {
        _ = self;
        switch (decl.*) {
            .function => |*func| {
                var fn_builder = FunctionBuilder(BasicBlock)
                    .init(arg.allocator, func.name);
                fn_builder.setReturnType(func.*.ret_ty);
                for (func.*.params) |*param| {
                    try fn_builder.addParam(param.*);
                }
                var bb_builder = BasicBlockBuilder.init(arg.allocator);
                errdefer bb_builder.deinit();
                var empty_bb_builder = true;
                for (func.*.elements) |*stmt| {
                    // Labeled statements start a new basic block
                    if (stmt.label) |label| {
                        // Edge case: empty basic blocks shouldn't build
                        if (!empty_bb_builder) {
                            const bb = try bb_builder.build();
                            try fn_builder.addElement(bb);
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
                        try bb_builder.setTerminator(stmt.*);
                        const bb = try bb_builder.build();
                        try fn_builder.addElement(bb);
                        bb_builder = BasicBlockBuilder.init(arg.allocator);
                    } else {
                        empty_bb_builder = false;
                        try bb_builder.addStatement(stmt.*);
                    }
                }
                // Maybe there's an implicit return, dunno if I wanna allow that
                if (!empty_bb_builder) {
                    const bb = try bb_builder.build();
                    try fn_builder.addElement(bb);
                }
                func.shallowDeinit(arg.allocator);
                decl.* = .{ .bb_function = fn_builder.build() catch unreachable };
            },
            .bb_function => {
                return error.AlreadyBlockified;
            },
            .builtin => {},
        }
    }
};

test "Changes all functions into BB functions" {
    const ProgramBuilder = @import("../nodes/program.zig").ProgramBuilder;
    var func_builder = FunctionBuilder(Stmt).init(std.testing.allocator, "main");

    try func_builder.addElement(Stmt.init(.{ .id = .{
        .name = "hi",
        .val = Value.initInt(99, Loc.default()),
        .ty = .int,
    } }, null, Loc.default()));
    const hi_access = Value.initAccessName("hi", Loc.default());
    try func_builder.addElement(Stmt.init(.{ .value = hi_access }, null, Loc.default()));
    const func_access = try std.testing.allocator.create(Value);
    func_access.* = Value.initAccessName("f", Loc.default());
    try func_builder.addElement(Stmt.init(.{ .value = Value.initCall(func_access, &.{}, Loc.default()) }, "testme", Loc.default()));

    const func = try func_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addDecl(Decl{ .function = func });
    var program = try prog_builder.build();

    // Better way to expect a tagged union value?
    switch (program.decls[0]) {
        .function => |main_func| try std.testing.expectEqual(main_func.elements.len, 3),
        .bb_function => try std.testing.expect(false),
        .builtin => try std.testing.expect(false),
    }

    var pass = BlockifyPass.init(.{ .allocator = std.testing.allocator });
    try pass.execute(&program);

    // Now it should be blockified
    switch (program.decls[0]) {
        .function => try std.testing.expect(false),
        .bb_function => |bb_func| try std.testing.expectEqual(bb_func.elements.len, 2),
        .builtin => try std.testing.expect(false),
    }

    program.deinit(std.testing.allocator);
}

// This may not always be necessary, but right now we only act on programs so
// it's all or nothing.
test "Errors when already blockified" {
    const ProgramBuilder = @import("../nodes/program.zig").ProgramBuilder;

    var func_builder = FunctionBuilder(BasicBlock).init(std.testing.allocator, "main");

    var bb1_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb1_builder.setLabel("bb1");
    try bb1_builder.addStatement(Stmt.init(.{ .id = .{
        .name = "hi",
        .val = Value.initInt(99, Loc.default()),
        .ty = .int,
    } }, null, Loc.default()));
    try func_builder.addElement(try bb1_builder.build());
    const func = try func_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addDecl(Decl{ .bb_function = func });
    var program = try prog_builder.build();

    var pass = BlockifyPass.init(.{ .allocator = std.testing.allocator });
    try std.testing.expectError(error.AlreadyBlockified, pass.execute(&program));

    program.deinit(std.testing.allocator);
}
