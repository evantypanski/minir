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
        LabelNotFound,
        ExpectedLabel,
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
                // Make a begin and end block
                var begin_builder = BasicBlockBuilder.init(arg.allocator);
                errdefer begin_builder.deinit();
                // TODO: How to better allocate a known string so that
                // it gets freed properly later?
                begin_builder.setLabel(try std.fmt.allocPrint(arg.allocator, "__begin", .{}));
                const begin = try begin_builder.build();
                try fn_builder.addElement(begin);

                var bb_builder = BasicBlockBuilder.init(arg.allocator);
                errdefer bb_builder.deinit();
                var empty_bb_builder = true;
                var bb_label_index: u64 = 0;
                for (func.*.elements) |*stmt| {
                    // Labeled statements start a new basic block
                    if (stmt.label) |label| {
                        // Edge case: empty basic blocks shouldn't build
                        if (!empty_bb_builder) {
                            const bb = try bb_builder.build();
                            try fn_builder.addElement(bb);
                            bb_builder = BasicBlockBuilder.init(arg.allocator);
                            errdefer bb_builder.deinit();
                        }
                        bb_builder.setLabel(try arg.allocator.dupe(u8, label));
                        // Remove its label
                        // TODO: Maybe this label should've been alloc'd
                        stmt.label = null;
                    } else if (bb_builder.label == null) {
                        bb_builder.setLabel(try std.fmt.allocPrint(arg.allocator, "__bb{d}", .{bb_label_index}));
                        bb_label_index += 1;
                    }
                    // Even if it has a label, we should go through this in
                    // case that labeled statement is a terminator.
                    if (stmt.isTerminator()) {
                        empty_bb_builder = true;
                        try bb_builder.setTerminator(stmt.*);
                        const bb = try bb_builder.build();
                        try fn_builder.addElement(bb);
                        bb_builder = BasicBlockBuilder.init(arg.allocator);
                        errdefer bb_builder.deinit();
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

                var end_builder = BasicBlockBuilder.init(arg.allocator);
                errdefer end_builder.deinit();
                end_builder.setLabel(try std.fmt.allocPrint(arg.allocator, "__end", .{}));
                const end = try end_builder.build();
                try fn_builder.addElement(end);

                func.shallowDeinit(arg.allocator);
                decl.* = .{ .bb_function = fn_builder.build() catch unreachable };

                try constructCfg(decl);
            },
            .bb_function => {
                return error.AlreadyBlockified;
            },
            .builtin => {},
        }
    }

    // Takes the basic blocks and connects them.
    pub fn constructCfg(decl: *Decl) Error!void {
        switch (decl.*) {
            .bb_function => |*func| {
                std.debug.assert(func.elements.len >= 2);
                // First element is begin, last is end.
                const begin = func.elements[0];
                const end = &func.elements[func.elements.len - 1];
                try func.elements[0].addNext(func.elements[1].label);
                try func.elements[1].addPrevious(begin.label);
                var bb_index: usize = 1;
                for (func.elements[bb_index .. func.elements.len - 1]) |*bb| {
                    if (bb.terminator) |*terminator| {
                        switch (terminator.stmt_kind) {
                            .ret, .unreachable_ => {
                                try bb.addNext(end.*.label);
                                try end.*.addPrevious(bb.*.label);
                            },
                            .branch => |*br| {
                                // Linear search for the label
                                for (func.elements, 0..) |*labeled, i| {
                                    if (std.mem.eql(u8, labeled.*.label, br.dest_label)) {
                                        // Found it!
                                        br.*.dest_index = i;
                                        try bb.addNext(labeled.label);
                                        try labeled.addPrevious(bb.label);
                                        break;
                                    }
                                } else {
                                    return error.LabelNotFound;
                                }
                            },
                            else => {},
                        }
                    } else {
                        try bb.addNext(func.elements[bb_index + 1].label);
                        try func.elements[bb_index + 1].addPrevious(bb.*.label);
                    }

                    bb_index += 1;
                }
            },
            .function, .builtin => {},
        }
    }
};

test "Changes all functions into BB functions" {
    const ProgramBuilder = @import("../nodes/program.zig").ProgramBuilder;
    var func_builder = FunctionBuilder(Stmt).init(std.testing.allocator, "main");

    try func_builder.addElement(Stmt.init(.{ .id = .{
        .name = "hi",
        .ssa_index = null,
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
    defer program.deinit(std.testing.allocator);

    // Better way to expect a tagged union value?
    switch (program.decls[0]) {
        .function => |main_func| try std.testing.expectEqual(main_func.elements.len, 3),
        .bb_function, .builtin => try std.testing.expect(false),
    }

    var pass = BlockifyPass.init(.{ .allocator = std.testing.allocator });
    try pass.execute(&program);

    // Now it should be blockified, two blocks plus begin/end
    switch (program.decls[0]) {
        .function => try std.testing.expect(false),
        .bb_function => |bb_func| try std.testing.expectEqual(bb_func.elements.len, 4),
        .builtin => try std.testing.expect(false),
    }
}

// This may not always be necessary, but right now we only act on programs so
// it's all or nothing.
test "Errors when already blockified" {
    const ProgramBuilder = @import("../nodes/program.zig").ProgramBuilder;

    var func_builder = FunctionBuilder(BasicBlock).init(std.testing.allocator, "main");

    var bb1_builder = BasicBlockBuilder.init(std.testing.allocator);
    errdefer bb1_builder.deinit();
    bb1_builder.setLabel(try std.fmt.allocPrint(std.testing.allocator, "bb1", .{}));
    try bb1_builder.addStatement(Stmt.init(.{ .id = .{
        .name = "hi",
        .ssa_index = null,
        .val = Value.initInt(99, Loc.default()),
        .ty = .int,
    } }, null, Loc.default()));
    try func_builder.addElement(try bb1_builder.build());
    const func = try func_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addDecl(Decl{ .bb_function = func });
    var program = try prog_builder.build();
    defer program.deinit(std.testing.allocator);

    var pass = BlockifyPass.init(.{ .allocator = std.testing.allocator });
    try std.testing.expectError(error.AlreadyBlockified, pass.execute(&program));
}
