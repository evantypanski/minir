const std = @import("std");

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const ChunkBuilder = @import("../../bytecode/chunk.zig").ChunkBuilder;
const Value = @import("../nodes/value.zig").Value;
const ByteValue = @import("../../bytecode/value.zig").Value;
const OpCode = @import("../../bytecode/opcodes.zig").OpCode;

const LowerError = error{
    MemoryError,
    BuilderError,
    VarNotInScope,
    InvalidLHS,
};

pub const Lowerer = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, LowerError!void);

    allocator: std.mem.Allocator,
    // Variables in scope.
    variables: [256] []const u8,
    num_locals: u8,
    // Number of parameters to the current function. This is used to determine
    // the offset signed/unsigned for getting locals.
    num_params: usize,
    builder: ChunkBuilder,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .variables = .{""} ** 256,
            .num_locals = 0,
            .num_params = 0,
            .builder = ChunkBuilder.init(allocator),
        };
    }

    pub const LowerVisitor = VisitorTy {
        .visitInt = visitInt,
        .visitDebug = visitDebug,
        .visitVarDecl = visitVarDecl,
        .visitValueStmt = visitValueStmt,
        .visitRet = visitRet,
        .visitBinaryOp = visitBinaryOp,
        .visitProgram = visitProgram,
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
        .visitVarAccess = visitVarAccess,
    };

    pub fn execute(self: *Self, program: *Program) LowerError!void {
        try LowerVisitor.visitProgram(LowerVisitor, self, program);
    }

    pub fn visitProgram(
        visitor: VisitorTy,
        self: *Self,
        program: *Program
    ) LowerError!void {
        // Add an undef value, index 0 will be undefined for all variables
        const val = ByteValue.initUndef();
        const idx = self.builder.addValue(val) catch return error.BuilderError;
        std.debug.assert(idx == 0);
        try visitor.walkProgram(self, program);
    }

    pub fn visitFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *Function(Stmt)
    ) LowerError!void {
        try self.addParams(function.*.params);
        try visitor.walkFunction(self, function);
    }

    pub fn visitBBFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *Function(BasicBlock)
    ) LowerError!void {
        try self.addParams(function.*.params);
        try visitor.walkBBFunction(self, function);
    }

    fn addParams(self: *Self, params: []VarDecl) LowerError!void {
        self.num_locals = 0;
        self.*.num_params = params.len;
        for (params) |param| {
            self.variables[self.num_locals] = param.name;
            self.num_locals += 1;
        }
    }

    pub fn visitDebug(
        visitor: VisitorTy,
        self: *Self,
        val: *Value)
    LowerError!void {
        try visitor.visitValue(visitor, self, val);
        self.builder.addOp(.debug) catch return error.BuilderError;
    }

    pub fn visitVarDecl(
        visitor: VisitorTy,
        self: *Self,
        decl: *VarDecl)
    LowerError!void {
        self.variables[self.num_locals] = decl.*.name;
        self.num_locals += 1;
        if (decl.*.val) |*val| {
            try visitor.visitValue(visitor, self, val);
        } else {
            self.builder.addOp(.constant) catch return error.BuilderError;
            // 0 is undef
            self.builder.addByte(0) catch return error.BuilderError;
        }
    }

    pub fn visitValueStmt(
        visitor: VisitorTy,
        self: *Self,
        val: *Value)
    LowerError!void {
        try visitor.visitValue(visitor, self, val);
        self.builder.addOp(.pop) catch return error.BuilderError;
    }

    pub fn visitRet(
        visitor: VisitorTy,
        self: *Self,
        opt_val: *?Value)
    LowerError!void {
        _ = visitor;
        _ = opt_val;
        // TODO: Return value
        self.builder.addOp(.ret) catch return error.BuilderError;
    }

    pub fn visitBinaryOp(
        visitor: VisitorTy,
        self: *Self,
        op: *Value.BinaryOp)
    LowerError!void {
        // Assign is special
        if (op.*.kind == .assign) {
            // This will need to change when we can set based on pointers etc.
            // Grab the variable offset.
            const offset = switch (op.*.lhs.*) {
                .access => |access| try self.getOffsetForName(access.name.?),
                else => return error.InvalidLHS,
            };
            try visitor.visitValue(visitor, self, op.*.rhs);
            try self.setVarOffset(offset);

            // Assign also pushes the value to the top of the stack
            try self.getVarOffset(offset);

            return;
        }

        // Ops are post order
        try visitor.visitValue(visitor, self, op.*.lhs);
        try visitor.visitValue(visitor, self, op.*.rhs);
        const op_opcode = switch (op.*.kind) {
            .add => OpCode.add,
            .sub => OpCode.sub,
            .mul => OpCode.mul,
            .div => OpCode.div,
            else => return,
        };
        self.builder.addOp(op_opcode) catch return error.BuilderError;
    }

    pub fn visitInt(visitor: VisitorTy, self: *Self, i: *i32) LowerError!void {
        _ = visitor;
        const val = ByteValue.initInt(i.*);
        const idx = self.builder.addValue(val) catch return error.BuilderError;
        self.builder.addOp(.constant) catch return error.BuilderError;
        self.builder.addByte(idx) catch return error.BuilderError;
    }

    pub fn visitVarAccess(
        visitor: VisitorTy,
        self: *Self,
        access: *Value.VarAccess
    ) LowerError!void {
        _ = visitor;
        const offset = try self.getOffsetForName(access.*.name.?);
        try self.getVarOffset(offset);
    }

    fn getOffsetForName(self: *Self, name: []const u8) LowerError!i8 {
        var i: u8 = 0;
        while (i < self.num_locals) : (i += 1) {
            if (std.mem.eql(u8, self.variables[i], name)) {
                return @intCast(i8, i) - @intCast(i8, self.*.num_params);
            }
        }

        return error.VarNotInScope;
    }

    // Gets variable at offset and pushes it to the stack.
    fn getVarOffset(self: *Self, offset: i8) LowerError!void {
        self.builder.addOp(.get) catch return error.BuilderError;
        self.builder.addByte(@bitCast(u8, offset))
            catch return error.BuilderError;
    }

    // Sets variable at offset with variable at the top of the stack.
    fn setVarOffset(self: *Self, offset: i8) LowerError!void {
        self.builder.addOp(.set) catch return error.BuilderError;
        self.builder.addByte(@bitCast(u8, offset))
            catch return error.BuilderError;
    }
};

