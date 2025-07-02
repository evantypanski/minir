const std = @import("std");

const Allocator = std.mem.Allocator;

const Provider = @import("util/pass.zig").Provider;
const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const Builtin = @import("../nodes/decl.zig").Builtin;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const Stmt = @import("../nodes/statement.zig").Stmt;
const Branch = @import("../nodes/statement.zig").Branch;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const ConstIrVisitor = @import("util/const_visitor.zig").ConstIrVisitor;
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
const InvalidBytecodeError = @import("../../bytecode/errors.zig").InvalidBytecodeError;

pub const Lower = Provider(Lowerer, Lowerer.Error, Chunk, &[_]type{}, Lowerer.init, Lowerer.execute);

pub const Lowerer = struct {
    pub const Error = error{
        VarNotInScope,
        InvalidLHS,
        NoSuchFunction,
        NoSuchLabel,
        InvalidBuiltin,
        InvalidType,
        BadArity,
    } || Allocator.Error || InvalidBytecodeError;

    const Self = @This();
    const VisitorTy = ConstIrVisitor(*Self, Error!void);

    allocator: Allocator,
    // Variables in scope.
    variables: [256][]const u8,
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

    pub fn init(args: anytype) Self {
        return .{
            .allocator = args.allocator,
            .variables = .{""} ** 256,
            .num_locals = 0,
            .num_params = 0,
            .builder = ChunkBuilder.init(args.allocator),
            .placeholder_map = std.StringHashMap(*std.ArrayList(usize)).init(args.allocator),
            .fn_map = std.StringHashMap(u16).init(args.allocator),
            .label_placeholder_map = std.StringHashMap(*std.ArrayList(usize)).init(args.allocator),
            .label_map = std.StringHashMap(u16).init(args.allocator),
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

    pub const LowerVisitor = VisitorTy{
        .visitStatement = visitStatement,
        .visitBasicBlock = visitBasicBlock,
        .visitInt = visitInt,
        .visitBool = visitBool,
        .visitVarDecl = visitVarDecl,
        .visitValueStmt = visitValueStmt,
        .visitRet = visitRet,
        .visitUnreachable = visitUnreachable,
        .visitUnaryOp = visitUnaryOp,
        .visitBinaryOp = visitBinaryOp,
        .visitProgram = visitProgram,
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
        .visitVarAccess = visitVarAccess,
        .visitFuncCall = visitFuncCall,
        .visitBranch = visitBranch,
    };

    pub fn execute(self: *Self, program: *const Program) Error!Chunk {
        errdefer self.builder.deinit();
        try LowerVisitor.visitProgram(LowerVisitor, self, program);
        return self.builder.build();
    }

    pub fn visitProgram(visitor: VisitorTy, self: *Self, program: *const Program) Error!void {
        // Add an undef value, index 0 will be undefined for all variables
        const val = ByteValue.initUndef();
        const idx = try self.builder.addValue(val);
        std.debug.assert(idx == 0);
        try visitor.walkProgram(self, program);
        try self.resolveFunctionCalls();
        try self.resolveBranches();
    }

    fn resolveFunctionCalls(self: *Self) Error!void {
        var it = self.*.placeholder_map.iterator();
        var opt_entry = it.next();
        while (opt_entry) |entry| {
            const addr = self.*.fn_map.get(entry.key_ptr.*) orelse return error.NoSuchFunction;
            for (entry.value_ptr.*.*.items) |placeholder| {
                try self.builder.setPlaceholderShort(placeholder, addr);
            }
            opt_entry = it.next();
        }
    }

    fn resolveBranches(self: *Self) Error!void {
        var it = self.*.label_placeholder_map.iterator();
        var opt_entry = it.next();
        while (opt_entry) |entry| {
            const addr = self.*.label_map.get(entry.key_ptr.*) orelse return error.NoSuchLabel;
            for (entry.value_ptr.*.*.items) |placeholder| {
                const offset_from =
                    self.builder.getPlaceholderShort(placeholder);
                const signed_addr: i16 = @intCast(addr);
                const signed_offset: i16 = @intCast(offset_from);
                const relative = signed_addr - signed_offset;
                try self.builder.setPlaceholderShort(placeholder, @bitCast(relative));
            }
            opt_entry = it.next();
        }
    }

    pub fn visitFunction(visitor: VisitorTy, self: *Self, function: *const Function(Stmt)) Error!void {
        try self.addParams(function.*.params);
        try self.fn_map.put(function.*.name, @intCast(self.builder.currentByte()));
        for (function.elements) |*stmt| {
            try visitor.visitStatement(visitor, self, stmt);
        }
    }

    pub fn visitBBFunction(visitor: VisitorTy, self: *Self, function: *const Function(BasicBlock)) Error!void {
        try self.addParams(function.*.params);
        try self.fn_map.put(function.*.name, @intCast(self.builder.currentByte()));
        for (function.elements) |*bb| {
            try visitor.visitBasicBlock(visitor, self, bb);
        }
    }

    fn addParams(self: *Self, params: []const VarDecl) Error!void {
        self.num_locals = 0;
        self.*.num_params = params.len;
        for (params) |param| {
            self.variables[self.num_locals] = param.name;
            self.num_locals += 1;
        }
    }

    pub fn visitStatement(visitor: VisitorTy, self: *Self, stmt: *const Stmt) Error!void {
        if (stmt.*.label) |label| {
            try self.label_map.put(label, @intCast(self.builder.currentByte()));
        }
        try visitor.walkStatement(self, stmt);
    }

    pub fn visitBasicBlock(visitor: VisitorTy, self: *Self, bb: *const BasicBlock) Error!void {
        try self.label_map.put(bb.label, @intCast(self.builder.currentByte()));
        try visitor.walkBasicBlock(self, bb);
    }

    pub fn visitVarDecl(visitor: VisitorTy, self: *Self, decl: *const VarDecl) Error!void {
        self.variables[self.num_locals] = decl.*.name;
        self.num_locals += 1;
        if (decl.*.val) |*val| {
            try visitor.visitValue(visitor, self, val);
        } else {
            try self.builder.addOp(.constant);
            // 0 is undef
            try self.builder.addByte(0);
        }
    }

    pub fn visitValueStmt(visitor: VisitorTy, self: *Self, val: *const Value) Error!void {
        try visitor.visitValue(visitor, self, val);
        try self.builder.addOp(.pop);
    }

    pub fn visitRet(visitor: VisitorTy, self: *Self, opt_val: *const ?Value) Error!void {
        // If there's a return value, it goes on the slot before parameters.
        // Otherwise it's already set as undefined
        if (opt_val.*) |*val| {
            try visitor.visitValue(visitor, self, val);
            const num_params: i8 = @intCast(self.num_params);
            try self.setVarOffset(-1 * num_params - 1);
        }

        try self.builder.addOp(.ret);
    }

    pub fn visitUnreachable(_: VisitorTy, self: *Self) Error!void {
        try self.builder.addOp(.unreachable_);
    }

    pub fn visitUnaryOp(visitor: VisitorTy, self: *Self, op: *const UnaryOp) Error!void {
        try visitor.visitValue(visitor, self, op.*.val);
        switch (op.*.kind) {
            .not => try self.builder.addOp(.not),
            .deref => {
                try self.builder.addOp(.deref);
                try self.builder.addByte(@sizeOf(ByteValue));
            },
            .neg => try self.builder.addOp(.neg),
        }
    }

    pub fn visitBinaryOp(visitor: VisitorTy, self: *Self, op: *const BinaryOp) Error!void {
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
                    try self.builder.addOp(.heapset);
                    try self.builder.addByte(@sizeOf(ByteValue));
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
        try self.builder.addOp(op_opcode);
    }

    pub fn visitInt(visitor: VisitorTy, self: *Self, i: *const i32) Error!void {
        _ = visitor;
        const val = ByteValue.initInt(i.*);
        const idx = try self.builder.addValue(val);
        try self.builder.addOp(.constant);
        try self.builder.addByte(idx);
    }

    pub fn visitBool(visitor: VisitorTy, self: *Self, b: *const u1) Error!void {
        _ = visitor;
        const val = ByteValue.initBool(b.* == 1);
        const idx = try self.builder.addValue(val);
        try self.builder.addOp(.constant);
        try self.builder.addByte(idx);
    }

    pub fn visitVarAccess(visitor: VisitorTy, self: *Self, access: *const VarAccess) Error!void {
        _ = visitor;
        const offset = try self.getOffsetForName(access.*.name.?);
        try self.getVarOffset(offset);
    }

    pub fn visitFuncCall(visitor: VisitorTy, self: *Self, call: *const FuncCall) Error!void {
        if (call.*.resolved) |resolved| {
            switch (resolved.*) {
                .builtin => |*builtin| return try self.lowerBuiltin(visitor, call, builtin),
                else => {},
            }
        }

        // Return value goes here
        try self.builder.addOp(.constant);
        // 0 is undef
        try self.builder.addByte(0);

        for (call.*.arguments) |*arg| {
            try visitor.visitValue(visitor, self, arg);
        }

        try self.builder.addOp(.call);
        const placeholder = try self.builder.addPlaceholderShort();

        const list = self.placeholder_map.get(call.*.name()) orelse blk: {
            const list = try self.allocator.create(std.ArrayList(usize));
            list.* = std.ArrayList(usize).init(self.allocator);
            try self.placeholder_map.put(call.*.name(), list);
            break :blk list;
        };
        try list.append(placeholder);

        // Pop each argument
        for (call.*.arguments) |_| {
            try self.builder.addOp(.pop);
        }
    }

    fn lowerBuiltin(self: *Self, visitor: VisitorTy, call: *const FuncCall, builtin: *const Builtin) Error!void {
        switch (builtin.*.kind) {
            .alloc => {
                try self.builder.addOp(.alloc);

                if (call.*.arguments.len != 1) {
                    return error.BadArity;
                }

                const tyVal = call.*.arguments[0];
                if (tyVal.val_kind != .type_) {
                    // Our own little typecheck
                    return error.InvalidType;
                }
                try self.builder.addByte(@intCast(tyVal.val_kind.type_.size()));
            },
            .debug => {
                // Push the "return value" so pop doesn't underflow
                try self.builder.addOp(.constant);
                try self.builder.addByte(0);

                if (call.*.arguments.len != 1) {
                    return error.BadArity;
                }
                try visitor.visitValue(visitor, self, &call.*.arguments[0]);

                try self.builder.addOp(.debug);
            },
        }
    }

    pub fn visitBranch(
        visitor: VisitorTy,
        self: *Self,
        branch: *const Branch,
    ) Error!void {
        var from_relative: usize = undefined;
        if (branch.expr) |*expr| {
            try visitor.visitValue(visitor, self, expr);
            from_relative = self.builder.currentByte();
            try self.builder.addOp(.jmpt);
        } else {
            from_relative = self.builder.currentByte();
            try self.builder.addOp(.jmp);
        }

        const placeholder = try self.builder.addPlaceholderShort();

        // Set the placeholder, for now, to the current byte. This will be
        // replaced with the relative address
        try self.builder.setPlaceholderShort(placeholder, @intCast(from_relative));

        const list = self.label_placeholder_map.get(branch.labelName()) orelse blk: {
            const list = try self.allocator.create(std.ArrayList(usize));
            list.* = std.ArrayList(usize).init(self.allocator);
            try self.label_placeholder_map.put(branch.labelName(), list);
            break :blk list;
        };
        try list.append(placeholder);
    }

    fn getOffsetForName(self: *Self, name: []const u8) Error!i8 {
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
    fn getVarOffset(self: *Self, offset: i8) Error!void {
        try self.builder.addOp(.get);
        try self.builder.addByte(@bitCast(offset));
    }

    // Sets variable at offset with variable at the top of the stack.
    fn setVarOffset(self: *Self, offset: i8) Error!void {
        try self.builder.addOp(.set);
        try self.builder.addByte(@bitCast(offset));
    }
};
