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
    builder: ChunkBuilder,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .variables = .{""} ** 256,
            .num_locals = 0,
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
        .visitVarAccess = visitVarAccess,
    };

    pub fn execute(self: *Self, program: *Program) LowerError!void {
        try LowerVisitor.visitProgram(LowerVisitor, self, program);
    }

    pub fn visitProgram(
        self: VisitorTy,
        arg: *Self,
        program: *Program
    ) LowerError!void {
        // Add an undef value, index 0 will be undefined for all variables
        const val = ByteValue.initUndef();
        const idx = arg.builder.addValue(val) catch return error.BuilderError;
        std.debug.assert(idx == 0);
        try self.walkProgram(arg, program);
    }

    pub fn visitDebug(
        self: VisitorTy,
        arg: *Self,
        val: *Value)
    LowerError!void {
        try self.visitValue(self, arg, val);
        arg.builder.addOp(.debug) catch return error.BuilderError;
    }

    pub fn visitVarDecl(
        self: VisitorTy,
        arg: *Self,
        decl: *VarDecl)
    LowerError!void {
        arg.variables[arg.num_locals] = decl.*.name;
        arg.num_locals += 1;
        if (decl.*.val) |*val| {
            try self.visitValue(self, arg, val);
        } else {
            arg.builder.addOp(.constant) catch return error.BuilderError;
            // 0 is undef
            arg.builder.addByte(0) catch return error.BuilderError;
        }
    }

    pub fn visitValueStmt(
        self: VisitorTy,
        arg: *Self,
        val: *Value)
    LowerError!void {
        try self.visitValue(self, arg, val);
        arg.builder.addOp(.pop) catch return error.BuilderError;
    }

    pub fn visitRet(
        self: VisitorTy,
        arg: *Self,
        opt_val: *?Value)
    LowerError!void {
        _ = self;
        _ = opt_val;
        // TODO: Return value
        arg.builder.addOp(.ret) catch return error.BuilderError;
    }

    pub fn visitBinaryOp(
        self: VisitorTy,
        arg: *Self,
        op: *Value.BinaryOp)
    LowerError!void {
        // Assign is special
        if (op.*.kind == .assign) {
            // This will need to change when we can set based on pointers etc.
            // Grab the variable offset.
            const offset = switch (op.*.lhs.*) {
                .access => |access| try arg.getOffsetForName(access.name.?),
                else => return error.InvalidLHS,
            };
            try self.visitValue(self, arg, op.*.rhs);
            try arg.setVarOffset(offset);

            // Assign also pushes the value to the top of the stack
            try arg.getVarOffset(offset);

            return;
        }

        // Ops are post order
        try self.visitValue(self, arg, op.*.lhs);
        try self.visitValue(self, arg, op.*.rhs);
        const op_opcode = switch (op.*.kind) {
            .add => OpCode.add,
            .sub => OpCode.sub,
            .mul => OpCode.mul,
            .div => OpCode.div,
            else => return,
        };
        arg.builder.addOp(op_opcode) catch return error.BuilderError;
    }

    pub fn visitInt(self: VisitorTy, arg: *Self, i: *i32) LowerError!void {
        _ = self;
        const val = ByteValue.initInt(i.*);
        const idx = arg.builder.addValue(val) catch return error.BuilderError;
        arg.builder.addOp(.constant) catch return error.BuilderError;
        arg.builder.addByte(idx) catch return error.BuilderError;
    }

    pub fn visitVarAccess(
        self: VisitorTy,
        arg: *Self,
        access: *Value.VarAccess
    ) LowerError!void {
        _ = self;
        const offset = try arg.getOffsetForName(access.*.name.?);
        try arg.getVarOffset(offset);
        return;
    }

    fn getOffsetForName(self: *Self, name: []const u8) LowerError!i8 {
        var i: u8 = 0;
        while (i < self.num_locals) : (i += 1) {
            if (std.mem.eql(u8, self.variables[i], name)) {
                return @intCast(i8, i);
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

