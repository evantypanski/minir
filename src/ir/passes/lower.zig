const std = @import("std");

const Allocator = std.mem.Allocator;

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const Builtin = @import("../nodes/decl.zig").Builtin;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const Stmt = @import("../nodes/statement.zig").Stmt;
const Branch = @import("../nodes/statement.zig").Branch;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Chunk = @import("../../bytecode/chunk.zig").Chunk;
const ChunkBuilder = @import("../../bytecode/chunk.zig").ChunkBuilder;
const Value = @import("../nodes/value.zig").Value;
const UnaryOp = @import("../nodes/value.zig").UnaryOp;
const FuncCall = @import("../nodes/value.zig").FuncCall;
const VarAccess = @import("../nodes/value.zig").VarAccess;
const BinaryOp = @import("../nodes/value.zig").BinaryOp;
const ByteValue = @import("../../bytecode/value.zig").Value;
const OpCode = @import("../../bytecode/opcodes.zig").OpCode;

const LowerError = error{
    MemoryError,
    BuilderError,
    VarNotInScope,
    InvalidLHS,
    NoSuchFunction,
    NoSuchLabel,
    InvalidBuiltin,
    InvalidType,
    BadArity,
};

pub const Lowerer = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, LowerError!void);

    allocator: Allocator,
    // Variables in scope.
    variables: [256] []const u8,
    num_locals: u8,
    // Number of parameters to the current function. This is used to determine
    // the offset signed/unsigned for getting locals.
    num_params: usize,
    builder: ChunkBuilder,
    // For function resolution, we keep a string map from function name to all
    // of the indexes in the chunk that need that absolute address. This should
    // eventually be replaced with some function table in the bytecode as a
    // header or something. But right now I don't care.
    placeholder_map: std.StringHashMap(*std.ArrayList(usize)),
    // Function name -> absolute address. Again shouldn't be necessary eventually
    fn_map: std.StringHashMap(u16),
    // Same as fn_map and placeholder_map, but for labels. Labels need a
    // different placeholder map because jumps use relative offsets.
    label_placeholder_map: std.StringHashMap(*std.ArrayList(usize)),
    label_map: std.StringHashMap(u16),

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .variables = .{""} ** 256,
            .num_locals = 0,
            .num_params = 0,
            .builder = ChunkBuilder.init(allocator),
            .placeholder_map =
                std.StringHashMap(*std.ArrayList(usize)).init(allocator),
            .fn_map = std.StringHashMap(u16).init(allocator),
            .label_placeholder_map =
                std.StringHashMap(*std.ArrayList(usize)).init(allocator),
            .label_map = std.StringHashMap(u16).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var placeholder_it = self.*.placeholder_map.iterator();
        var placeholder_opt_entry = placeholder_it.next();
        while (placeholder_opt_entry) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            placeholder_opt_entry = placeholder_it.next();
        }
        self.placeholder_map.clearAndFree();
        self.fn_map.clearAndFree();
        var label_placeholder_it = self.*.label_placeholder_map.iterator();
        var label_placeholder_opt_entry = label_placeholder_it.next();
        while (label_placeholder_opt_entry) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            label_placeholder_opt_entry = label_placeholder_it.next();
        }
        self.label_placeholder_map.clearAndFree();
        self.label_map.clearAndFree();
    }

    pub const LowerVisitor = VisitorTy {
        .visitStatement = visitStatement,
        .visitBasicBlock = visitBasicBlock,
        .visitInt = visitInt,
        .visitVarDecl = visitVarDecl,
        .visitValueStmt = visitValueStmt,
        .visitRet = visitRet,
        .visitUnaryOp = visitUnaryOp,
        .visitBinaryOp = visitBinaryOp,
        .visitProgram = visitProgram,
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
        .visitVarAccess = visitVarAccess,
        .visitFuncCall = visitFuncCall,
        .visitBranch = visitBranch,
    };

    pub fn execute(self: *Self, program: *Program) !Chunk {
        errdefer self.builder.deinit();
        try LowerVisitor.visitProgram(LowerVisitor, self, program);
        return self.builder.build();
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
        try self.resolveFunctionCalls();
        try self.resolveBranches();
    }

    fn resolveFunctionCalls(self: *Self) LowerError!void {
        var it = self.*.placeholder_map.iterator();
        var opt_entry = it.next();
        while (opt_entry) |entry| {
            const addr = self.*.fn_map.get(entry.key_ptr.*)
                orelse return error.NoSuchFunction;
            for (entry.value_ptr.*.*.items) |placeholder| {
                self.builder.setPlaceholderShort(placeholder, addr)
                    catch return error.BuilderError;
            }
            opt_entry = it.next();
        }
    }

    fn resolveBranches(self: *Self) LowerError!void {
        var it = self.*.label_placeholder_map.iterator();
        var opt_entry = it.next();
        while (opt_entry) |entry| {
            const addr = self.*.label_map.get(entry.key_ptr.*)
                orelse return error.NoSuchLabel;
            for (entry.value_ptr.*.*.items) |placeholder| {
                const offset_from =
                    self.builder.getPlaceholderShort(placeholder);
                const signed_addr: i16 = @intCast(addr);
                const signed_offset: i16 = @intCast(offset_from);
                const relative = signed_addr - signed_offset;
                self.builder.setPlaceholderShort(
                    placeholder,
                    @bitCast(relative)
                ) catch return error.BuilderError;
            }
            opt_entry = it.next();
        }
    }

    pub fn visitFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *Function(Stmt)
    ) LowerError!void {
        try self.addParams(function.*.params);
        self.fn_map.put(
            function.*.name,
            @intCast(self.builder.currentByte())
        ) catch return error.MemoryError;
        try visitor.walkFunction(self, function);
    }

    pub fn visitBBFunction(
        visitor: VisitorTy,
        self: *Self,
        function: *Function(BasicBlock)
    ) LowerError!void {
        try self.addParams(function.*.params);
        self.fn_map.put(
            function.*.name,
            @intCast(self.builder.currentByte())
        ) catch return error.MemoryError;
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

    pub fn visitStatement(
        visitor: VisitorTy,
        self: *Self,
        stmt: *Stmt
    ) LowerError!void {
        if (stmt.*.label) |label| {
            self.label_map.put(
                label,
                @intCast(self.builder.currentByte())
            ) catch return error.MemoryError;
        }
        try visitor.walkStatement(self, stmt);
    }

    pub fn visitBasicBlock(
        visitor: VisitorTy,
        self: *Self,
        bb: *BasicBlock
    ) LowerError!void {
        if (bb.*.label) |label| {
            self.label_map.put(
                label,
                @intCast(self.builder.currentByte())
            ) catch return error.MemoryError;
        }
        try visitor.walkBasicBlock(self, bb);
    }

    pub fn visitVarDecl(
        visitor: VisitorTy,
        self: *Self,
        decl: *VarDecl
    ) LowerError!void {
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
        val: *Value
    ) LowerError!void {
        try visitor.visitValue(visitor, self, val);
        self.builder.addOp(.pop) catch return error.BuilderError;
    }

    pub fn visitRet(
        visitor: VisitorTy,
        self: *Self,
        opt_val: *?Value
    ) LowerError!void {
        // If there's a return value, it goes on the slot before parameters.
        // Otherwise it's already set as undefined
        if (opt_val.*) |*val| {
            try visitor.visitValue(visitor, self, val);
            const num_params: i8 = @intCast(self.num_params);
            try self.setVarOffset(-1 * num_params - 1);
        }

        self.builder.addOp(.ret) catch return error.BuilderError;
    }

    pub fn visitUnaryOp(
        visitor: VisitorTy,
        self: *Self,
        op: *UnaryOp
    ) LowerError!void {
        try visitor.visitValue(visitor, self, op.*.val);
        switch (op.*.kind) {
            .not => self.builder.addOp(.not) catch return error.BuilderError,
            .deref => {
                self.builder.addOp(.deref) catch return error.BuilderError;
                self.builder.addByte(@sizeOf(ByteValue))
                        catch return error.BuilderError;
            },
            .neg => self.builder.addOp(.neg) catch return error.BuilderError,
        }
    }

    pub fn visitBinaryOp(
        visitor: VisitorTy,
        self: *Self,
        op: *BinaryOp
    ) LowerError!void {
        // Assign is special
        if (op.*.kind == .assign) {
            try visitor.visitValue(visitor, self, op.*.rhs);
            switch (op.*.lhs.*.val_kind) {
                // Simple variable access, so set is fine
                .access => |access| {
                    const offset = try self.getOffsetForName(access.name.?);
                    try self.setVarOffset(offset);
                    try self.getVarOffset(offset);
                },
                .unary => |uo| {
                    if (uo.kind != .deref) {
                        return error.InvalidLHS;
                    }

                    try visitor.visitValue(visitor, self, uo.val);
                    // Skip tho deref so we can get the pointer val with
                    // heapset
                    self.builder.addOp(.heapset) catch return error.BuilderError;
                    self.builder.addByte(@sizeOf(ByteValue))
                            catch return error.BuilderError;
                    // Then put derefed value at top of the stack, which is
                    // just the op's LHS
                    try visitor.visitValue(visitor, self, op.*.lhs);
                },
                else => return error.InvalidLHS,
            }

            // Assign also pushes the value to the top of the stack

            return;
        }

        // Ops are post order
        try visitor.visitValue(visitor, self, op.*.lhs);
        try visitor.visitValue(visitor, self, op.*.rhs);
        const op_opcode = switch (op.*.kind) {
            .eq => OpCode.eq,
            .add => OpCode.add,
            .sub => OpCode.sub,
            .mul => OpCode.mul,
            .div => OpCode.div,
            .and_ => OpCode.and_,
            .or_ => OpCode.or_,
            .lt => OpCode.lt,
            .le => OpCode.le,
            .gt => OpCode.gt,
            .ge => OpCode.ge,
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
        access: *VarAccess
    ) LowerError!void {
        _ = visitor;
        const offset = try self.getOffsetForName(access.*.name.?);
        try self.getVarOffset(offset);
    }

    pub fn visitFuncCall(
        visitor: VisitorTy,
        self: *Self,
        call: *FuncCall
    ) LowerError!void {
        if (call.*.resolved) |resolved| {
            switch (resolved.*) {
                .builtin => |*builtin| return try self.lowerBuiltin(visitor, call, builtin),
                else => {},
            }
        }

        // Return value goes here
        self.builder.addOp(.constant) catch return error.BuilderError;
        // 0 is undef
        self.builder.addByte(0) catch return error.BuilderError;

        for (call.*.arguments) |*arg| {
            try visitor.visitValue(visitor, self, arg);
        }

        self.builder.addOp(.call) catch return error.BuilderError;
        const placeholder = self.builder.addPlaceholderShort()
            catch return error.BuilderError;

        const list = self.placeholder_map.get(call.*.name()) orelse blk: {
            const list = self.allocator.create(std.ArrayList(usize))
                catch return error.MemoryError;
            list.* = std.ArrayList(usize).init(self.allocator);
            self.placeholder_map.put(call.*.name(), list)
                catch return error.MemoryError;
            break :blk list;
        };
        list.append(placeholder) catch return error.MemoryError;

        // Pop each argument
        for (call.*.arguments) |_| {
            self.builder.addOp(.pop) catch return error.BuilderError;
        }
    }

    fn lowerBuiltin(
        self: *Self,
        visitor: VisitorTy,
        call: *FuncCall,
        builtin: *const Builtin
    ) LowerError!void {
        switch (builtin.*.kind) {
            .alloc => {
                self.builder.addOp(.alloc) catch return error.BuilderError;

                if (call.*.arguments.len != 1) {
                    return error.BadArity;
                }

                const tyVal = call.*.arguments[0];
                if (tyVal.val_kind != .type_) {
                    // Our own little typecheck
                    return error.InvalidType;
                }
                self.builder.addByte(@intCast(tyVal.val_kind.type_.size()))
                        catch return error.BuilderError;
            },
            .debug => {
                // Push the "return value" so pop doesn't underflow
                self.builder.addOp(.constant) catch return error.BuilderError;
                self.builder.addByte(0) catch return error.BuilderError;

                if (call.*.arguments.len != 1) {
                    return error.BadArity;
                }
                try visitor.visitValue(visitor, self, &call.*.arguments[0]);

                self.builder.addOp(.debug) catch return error.BuilderError;
            },
        }
    }

    pub fn visitBranch(
        visitor: VisitorTy,
        self: *Self,
        branch: *Branch,
    ) LowerError!void {
        var from_relative: usize = undefined;
        if (branch.expr) |*expr| {
            try visitor.visitValue(visitor, self, expr);
            from_relative = self.builder.currentByte();
            self.builder.addOp(.jmpt) catch return error.BuilderError;
        } else {
            from_relative = self.builder.currentByte();
            self.builder.addOp(.jmp) catch return error.BuilderError;
        }

        const placeholder = self.builder.addPlaceholderShort()
            catch return error.BuilderError;

        // Set the placeholder, for now, to the current byte. This will be
        // replaced with the relative address
        self.builder.setPlaceholderShort(
            placeholder,
            @intCast(from_relative)
        ) catch return error.BuilderError;


        const list = self.label_placeholder_map.get(branch.labelName())
            orelse blk: {
                const list = self.allocator.create(std.ArrayList(usize))
                    catch return error.MemoryError;
                list.* = std.ArrayList(usize).init(self.allocator);
                self.label_placeholder_map.put(branch.labelName(), list)
                    catch return error.MemoryError;
                break :blk list;
        };
        list.append(placeholder) catch return error.MemoryError;
    }

    fn getOffsetForName(self: *Self, name: []const u8) LowerError!i8 {
        var i: u8 = 0;
        while (i < self.num_locals) : (i += 1) {
            if (std.mem.eql(u8, self.variables[i], name)) {
                const signed_i: i8 = @intCast(i);
                const signed_num_params: i8 = @intCast(self.*.num_params);
                return signed_i - signed_num_params;
            }
        }

        return error.VarNotInScope;
    }

    // Gets variable at offset and pushes it to the stack.
    fn getVarOffset(self: *Self, offset: i8) LowerError!void {
        self.builder.addOp(.get) catch return error.BuilderError;
        self.builder.addByte(@bitCast(offset))
            catch return error.BuilderError;
    }

    // Sets variable at offset with variable at the top of the stack.
    fn setVarOffset(self: *Self, offset: i8) LowerError!void {
        self.builder.addOp(.set) catch return error.BuilderError;
        self.builder.addByte(@bitCast(offset))
            catch return error.BuilderError;
    }
};

