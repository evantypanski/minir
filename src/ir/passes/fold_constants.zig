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

const FoldError = error{
    MemoryError,
};

pub const FoldConstantsPass = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, FoldError!void);

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub const FoldVisitor = VisitorTy {
        .visitValue = visitValue,
    };

    pub fn execute(self: *Self, program: *Program) FoldError!void {
        try FoldVisitor.visitProgram(FoldVisitor, self, program);
    }

    pub fn visitValue(
        visitor: VisitorTy,
        self: *Self,
        val: *Value
    ) FoldError!void {
        switch (val.*) {
            .binary => |*op| {
                switch (op.*.kind) {
                    .add => {
                        const lhs = switch (op.*.lhs.*) {
                            .int => |lhs| lhs,
                            else => return try visitor.visitBinaryOp(
                                        visitor, self, op
                                    ),
                        };
                        const rhs = switch (op.*.rhs.*) {
                            .int => |rhs| rhs,
                            else => return try visitor.visitBinaryOp(
                                        visitor, self, op
                                    ),
                        };
                        // Apply since both LHS and RHS are ints
                        const new_int = lhs + rhs;
                        val.*.deinit(self.allocator);
                        val.* = Value.initInt(new_int);
                    },
                    else => try visitor.visitBinaryOp(visitor, self, op),
                }
            },
            else => try visitor.walkValue(self, val),
        }
    }
};
