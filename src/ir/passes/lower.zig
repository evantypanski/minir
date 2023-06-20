const std = @import("std");

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const ChunkBuilder = @import("../../bytecode/chunk.zig").ChunkBuilder;
const Value = @import("../../bytecode/value.zig").Value;

const LowerError = error{
    MemoryError,
    BuilderError,
};

pub const Lowerer = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, LowerError!void);

    allocator: std.mem.Allocator,
    builder: ChunkBuilder,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .builder = ChunkBuilder.init(allocator),
        };
    }

    pub const LowerVisitor = VisitorTy {
        .visitInt = visitInt,
        .visitProgram = visitProgram,
    };

    pub fn execute(self: *Self, program: *Program) LowerError!void {
        try LowerVisitor.visitProgram(LowerVisitor, self, program);
    }

    pub fn visitProgram(self: VisitorTy, arg: *Self, program: *Program) LowerError!void {
        try self.walkProgram(arg, program);
        arg.builder.addOp(.ret) catch return error.BuilderError;
    }
    pub fn visitInt(self: VisitorTy, arg: *Self, i: *i32) LowerError!void {
        _ = self;
        const val = Value.initInt(i.*);
        const idx = arg.builder.addValue(val) catch return error.BuilderError;
        arg.builder.addOp(.constant) catch return error.BuilderError;
        arg.builder.addByte(idx) catch return error.BuilderError;
        arg.builder.addOp(.debug) catch return error.BuilderError;
        //std.debug.print("FOUND INT {}\n", .{i});
    }
};

