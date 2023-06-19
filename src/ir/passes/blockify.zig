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
