const std = @import("std");

const Allocator = std.mem.Allocator;

const Modifier = @import("util/pass.zig").Modifier;
const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const Value = @import("../nodes/value.zig").Value;
const IrVisitor = @import("util/visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;

pub const FoldConstants = Modifier(FoldConstantsPass, FoldConstantsPass.Error, &[_]type{}, FoldConstantsPass.init, FoldConstantsPass.execute);

pub const FoldConstantsPass = struct {
    pub const Error = error{};

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

    pub const FoldVisitor = VisitorTy{
        .visitValue = visitValue,
    };

    pub fn execute(self: *Self, program: *Program) Error!void {
        try FoldVisitor.visitProgram(FoldVisitor, self, program);
    }

    pub fn visitValue(visitor: VisitorTy, self: *Self, val: *Value) Error!void {
        switch (val.*.val_kind) {
            .binary => |*op| {
                switch (op.*.kind) {
                    .add => {
                        const lhs = switch (op.*.lhs.*.val_kind) {
                            .int => |lhs| lhs,
                            else => return try visitor.visitBinaryOp(visitor, self, op),
                        };
                        const rhs = switch (op.*.rhs.*.val_kind) {
                            .int => |rhs| rhs,
                            else => return try visitor.visitBinaryOp(visitor, self, op),
                        };
                        // Apply since both LHS and RHS are ints
                        const new_int = lhs + rhs;
                        const loc = val.loc;
                        val.*.deinit(self.allocator);
                        val.* = Value.initInt(new_int, loc);
                    },
                    else => try visitor.visitBinaryOp(visitor, self, op),
                }
            },
            else => try visitor.walkValue(self, val),
        }
    }
};
