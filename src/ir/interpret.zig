// This file will probably disappear when a good enough bytecode gets up to speed
const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Writer = std.fs.File.Writer;

const IrError = @import("errors.zig").IrError;
const Loc = @import("sourceloc.zig").Loc;
const Function = @import("nodes/decl.zig").Function;
const Stmt = @import("nodes/statement.zig").Stmt;
const Program = @import("nodes/program.zig").Program;
const Value = @import("nodes/value.zig").Value;
const UnaryOp = @import("nodes/value.zig").UnaryOp;
const BinaryOp = @import("nodes/value.zig").BinaryOp;
const FuncCall = @import("nodes/value.zig").FuncCall;
const Decl = @import("nodes/decl.zig").Decl;
const Builtin = @import("nodes/decl.zig").Builtin;
const Type = @import("nodes/type.zig").Type;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;
const Heap = @import("memory.zig").Heap;

const Frame = struct {
    frame_env_begin: usize,
    return_ele_index: usize,
};

pub const Interpreter = struct {
    const Self = @This();

    writer: Writer,
    program: Program,
    // The current basic block's index getting executed.
    // Will start and end as null.
    current_ele: ?usize,
    env: ArrayList(Value),
    call_stack: ArrayList(Frame),
    heap: Heap,

    pub fn init(allocator: Allocator, writer: Writer, program: Program) !Self {
        return .{
            .writer = writer,
            .program = program,
            .current_ele = null,
            .env = try ArrayList(Value).initCapacity(allocator, 50),
            .call_stack = ArrayList(Frame).init(allocator),
            .heap = try Heap.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.env.clearAndFree();
        self.call_stack.clearAndFree();
    }

    pub fn interpret(self: *Self) IrError!void {
        var main_fn: ?Decl = null;
        for (self.program.decls) |decl| {
            if (std.mem.eql(u8, decl.name(), "main")) {
                main_fn = decl;
                break;
            }
        } else {
            return error.NoMainFunction;
        }

        self.current_ele = 0;
        try self.pushFrame();
        // For now ignore main return
        try self.interpretDecl(main_fn.?);
        _ = self.popFrame();
    }

    pub fn interpretDecl(self: *Self, decl: Decl) IrError!void {
        switch (decl) {
            .function => |function| try self.interpretFn(function),
            .bb_function => |bb_function| try self.interpretBBFn(bb_function),
            .builtin => |builtin| try self.interpretBuiltin(builtin),
        }
    }

    pub fn interpretFn(self: *Self, function: Function(Stmt)) IrError!void {
        self.current_ele = 0;
        while (self.current_ele) |idx| {
            // May go off edge
            if (function.elements.len <= idx) {
                return;
            }

            const stmt = function.elements[idx];
            try self.evalStmt(stmt);
            if (!stmt.isTerminator()) {
                if (self.current_ele) |*current_ele| {
                    current_ele.* += 1;
                }
            }
        }
    }

    pub fn interpretBBFn(self: *Self, function: Function(BasicBlock)) IrError!void {
        self.current_ele = 0;
        while (self.current_ele) |bb_idx| {
            // May go off edge
            if (function.elements.len <= bb_idx) {
                return;
            }

            const bb = function.elements[bb_idx];
            for (bb.statements) |stmt| {
                try self.evalStmt(stmt);
            }

            if (bb.terminator) |terminator| {
                try self.evalTerminator(terminator);
            } else {
                if (self.current_ele) |*current_ele| {
                    current_ele.* += 1;
                }
            }
        }
    }

    fn evalStmt(self: *Self, stmt: Stmt) IrError!void {
        switch (stmt.stmt_kind) {
            .debug => |value| {
                // Evaluate binary ops etc.
                try self.evalValue(value);
                try self.printValue(self.env.pop());
            },
            .id => |vd| {
                if (vd.val) |val| {
                    try self.evalValue(val);
                } else {
                    try self.pushValue(Value.initUndef(Loc.default()));
                }
            },
            .value => |value| {
                try self.evalValue(value);
                // Remove the value pushed to stack
                _ = self.env.pop();
            },
            .branch, .ret => try self.evalTerminator(stmt),
        }
    }

    fn evalTerminator(self: *Self, stmt: Stmt) IrError!void {
        switch (stmt.stmt_kind) {
            .debug, .id, .value => return error.ExpectedTerminator,
            .branch => |branch| {
                if (branch.expr) |val| {
                    try self.evalValue(val);
                    const result = self.env.pop();
                    if (!try (try self.evalBool(result)).asBool()) {
                        // Go to next basic block and return
                        if (self.current_ele) |*current_ele| {
                            current_ele.* += 1;
                        }

                        return;
                    }
                }

                self.current_ele = branch.dest_index;
            },
            .ret => |opt_val| {
                if (opt_val) |val| {
                    try self.evalValue(val);
                }
                self.current_ele = null;
            },
        }
    }

    fn getAbsoluteOffset(self: Self, offset: isize) usize {
        const frame_begin = self.call_stack.getLast().frame_env_begin;
        const signed_begin: isize = @intCast(frame_begin);
        const index = signed_begin + offset;
        return @intCast(index);
    }

    // Gets the current runtime value from an offset
    fn getAccessValOffset(self: Self, offset: isize) IrError!Value {
        return self.env.items[self.getAbsoluteOffset(offset)];
    }

    // Evaluates a given value as a boolean, or returns an error if it
    // cannot be coerced.
    fn evalBool(self: *Self, value: Value) IrError!Value {
        switch (value.val_kind) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    return self.evalBool(try self.getAccessValOffset(offset));
                } else {
                    return error.ExpectedNumifiedAccess;
                }
            },
            .int, .float, .type_, .ptr => return error.TypeError,
            .bool => return value,
            .call => |call| {
                const ret = try self.evalCall(call);
                if (ret) |val| {
                    return self.evalBool(val);
                } else {
                    return error.ExpectedReturn;
                }
            },
            .unary => {
                self.evalValue(value) catch return error.InvalidBool;
                const val = self.env.pop();
                return self.evalBool(val) catch return error.InvalidBool;
            },
            .binary => {
                self.evalValue(value) catch return error.InvalidBool;
                const val = self.env.pop();
                return self.evalBool(val) catch return error.InvalidBool;
            },
        }
    }

    // Evaluates a given value as a type value, or returns an error if it
    // cannot be coerced.
    fn evalType(self: *Self, value: Value) IrError!Value {
        switch (value.val_kind) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    return self.evalType(try self.getAccessValOffset(offset));
                } else {
                    return error.ExpectedNumifiedAccess;
                }
            },
            .int, .float, .bool, .unary, .binary, .ptr => return error.TypeError,
            .call => |call| {
                const ret = try self.evalCall(call);
                if (ret) |val| {
                    return self.evalType(val);
                } else {
                    return error.ExpectedReturn;
                }
            },
            .type_ => return value,
        }
    }

    fn evalUnaryOp(self: *Self, op: UnaryOp) IrError!void {
        switch (op.kind) {
            .not => {
                self.evalValue(op.val.*) catch return error.OperandError;
                var boolVal = try self.evalBool(self.env.getLast());
                // This will always be boolean but recover nicely anyway
                switch (boolVal.val_kind) {
                    .bool => |*b| b.* = @intFromBool(b.* != 1),
                    else => return error.InvalidBool,
                }
                try self.pushValue(boolVal);
            },
            .deref => {
                self.evalValue(op.val.*) catch return error.OperandError;
                const ptrVal = self.env.pop();
                const ptr = try ptrVal.asPtr();
                const bytes = self.heap.getBytes(ptr.to, ptr.ty.size());
                try self.pushValue(std.mem.bytesAsValue(Value, bytes[0..@sizeOf(Value)]).*);
            },
            .neg => {
                self.evalValue(op.val.*) catch return error.OperandError;
                const numVal = self.env.pop();
                // TODO: Fix locs to include the op, but UnaryOp doesn't
                // have a reference to its whole loc
                switch (numVal.val_kind) {
                    .int => |i| try self.pushValue(
                        Value.initInt(-1 * i, op.val.*.loc)
                    ),
                    .float => |f| try self.pushValue(
                        Value.initFloat(-1 * f, op.val.*.loc)
                    ),
                    else => return error.OperandError,
                }
            },
        }
    }

    // Pops two values off the stack, performs the given operator on them,
    // then pushes the result onto the stack.
    fn evalBinaryOp(self: *Self, op: BinaryOp) IrError!void {
        // Special ops that don't just pop both values off and do a thing
        switch (op.kind) {
            .assign => {
                switch (op.lhs.*.val_kind) {
                    .access => |va| {
                        const index = if (va.offset) |offset|
                            offset
                        else
                            return error.ExpectedNumifiedAccess;
                        self.evalValue(op.rhs.*) catch return error.OperandError;
                        const rhs = self.env.getLast();
                        self.env.items[self.getAbsoluteOffset(index)] = rhs;
                        return;
                    },
                    .unary => |uo| {
                        // Get the pointer
                        if (uo.kind != .deref) return error.InvalidLHSAssign;
                        self.evalValue(uo.val.*) catch return error.OperandError;
                        const ptrVal = self.env.pop();
                        const ptr = try ptrVal.asPtr();
                        self.evalValue(op.rhs.*) catch return error.OperandError;
                        const rhs = self.env.getLast();
                        self.heap.setBytes(ptr.to, std.mem.toBytes(rhs)[0..]);
                        return;
                    },
                    else => return error.InvalidLHSAssign,
                }
            },
            .and_ => {
                self.evalValue(op.lhs.*) catch return error.OperandError;
                const newLHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                if (!try newLHS.asBool()) {
                    // Replace stack value with the new bool
                    try self.pushValue(newLHS);
                    return;
                }

                self.evalValue(op.rhs.*) catch return error.OperandError;
                const newRHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                // Now append the result which is just the RHS
                try self.pushValue(newRHS);
                return;
            },
            .or_ => {
                self.evalValue(op.lhs.*) catch return error.OperandError;
                const newLHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                if (!try newLHS.asBool()) {
                    // Replace stack value with the new bool
                    try self.pushValue(newLHS);
                    return;
                }

                self.evalValue(op.rhs.*) catch return error.OperandError;
                const newRHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                // Now append the result which is just the RHS
                try self.pushValue(newRHS);
                return;
            },
            else => {},
        }

        self.evalValue(op.lhs.*) catch return error.OperandError;
        const lhs = self.env.pop();
        self.evalValue(op.rhs.*) catch return error.OperandError;
        const rhs = self.env.pop();
        const newloc = Loc.combine(op.lhs.*.loc, op.rhs.*.loc);

        switch (op.kind) {
            .eq => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() == try rhs.asInt(), newloc)
                );
            },
            .add => {
                try self.pushValue(
                    Value.initInt(try lhs.asInt() + try rhs.asInt(), newloc)
                );
            },
            .sub => {
                try self.pushValue(
                    Value.initInt(try lhs.asInt() - try rhs.asInt(), newloc)
                );
            },
            .mul => {
                try self.pushValue(
                    Value.initInt(try lhs.asInt() * try rhs.asInt(), newloc)
                );
            },
            .div => {
                try self.pushValue(
                    Value.initInt(
                        @divTrunc(try lhs.asInt(), try rhs.asInt()),
                        newloc,
                    )
                );
            },
            .lt => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() < try rhs.asInt(), newloc)
                );
            },
            .le => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() <= try rhs.asInt(), newloc)
                );
            },
            .gt => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() > try rhs.asInt(), newloc)
                );
            },
            .ge => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() >= try rhs.asInt(), newloc)
                );
            },
            else => unreachable,
        }
    }

    fn evalValue(self: *Self, value: Value) IrError!void {
        switch (value.val_kind) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    try self.evalValue(try self.getAccessValOffset(offset));
                } else {
                    return error.ExpectedNumifiedAccess;
                }
            },
            .int, .float, .bool, .type_, .ptr => try self.pushValue(value),
            .unary => |op| {
                try self.evalUnaryOp(op);
            },
            .binary => |op| {
                try self.evalBinaryOp(op);
            },
            .call => |call| {
                const ret = try self.evalCall(call);
                if (ret) |val| {
                    try self.pushValue(val);
                } else {
                    // Void function should get undef pushed. This should be
                    // done better.
                    try self.pushValue(Value.initUndef(Loc.default()));
                }
            },
        }
    }

    fn evalCall(self: *Self, call: FuncCall) IrError!?Value {
        for (call.arguments) |arg| {
            try self.evalValue(arg);
        }
        // TODO: We make assumptions here that should be analyzed, like a
        // return type actually means a value is returned.
        const func = call.resolved orelse return error.NoSuchFunction;
        try self.pushFrame();
        defer {
            const frame = self.popFrame();
            self.current_ele = frame.return_ele_index;
        }
        try self.interpretDecl(func.*);
        if (func.ty() != .none) {
            try self.evalValue(self.env.pop());
            const ret = self.env.pop();
            return ret;
        }

        return null;
    }

    fn interpretBuiltin(self: *Self, builtin: Builtin) IrError!void {
        switch (builtin.kind) {
            .alloc => {
                const val_ty = self.env.pop();
                const allocated = try self.allocateType(val_ty.val_kind.type_);
                try self.pushValue(allocated);
            }
        }
    }

    // Allocates a type on the stack and returns a Value with a pointer
    // to that spot
    fn allocateType(self: *Self, ty: Type) IrError!Value {
        const to = try self.heap.alloc(ty.size());
        return Value.initPtr(to, ty, Loc.default());
    }

    fn pushFrame(self: *Self) IrError!void {
        self.call_stack.append(.{
            .frame_env_begin = self.env.items.len,
            .return_ele_index = self.current_ele.?
        }) catch return error.FrameError;
    }

    fn popFrame(self: *Self) Frame {
        return self.call_stack.pop();
    }

    fn pushValue(self: *Self, value: Value) IrError!void {
        self.env.append(value) catch return error.StackError;
    }

    fn printValue(self: *Self, value: Value) IrError!void {
        switch (value.val_kind) {
            .undef => self.writer.writeAll("undefined")
                    catch return error.WriterError,
            .access => |va| {
                if (va.name) |name| {
                    self.writer.writeAll(name)
                            catch return error.WriterError;
                }
            },
            .int => |i| fmt.formatInt(i, 10, .lower, .{}, self.writer)
                    catch return error.WriterError,
            .float => |f| {
                var buf: [fmt.format_float.bufferSize(.decimal, f32)]u8 = undefined;
                const s = fmt.format_float.formatFloat(&buf, f, .{})
                        catch return error.WriterError;
                fmt.formatBuf(s, .{}, self.writer) catch return error.WriterError;
            },
            .bool => |b| self.writer.print("{}", .{b})
                    catch return error.WriterError,
            .call => |call| {
                self.writer.print("{s}(", .{call.name()})
                        catch return error.WriterError;
                self.writer.writeAll(")")
                        catch return error.WriterError;
            },
            .ptr => |ptr| self.writer.print("@{d}", .{ptr.to})
                    catch return error.WriterError,
            else => return error.InvalidValue,
        }

        self.writer.writeAll("\n") catch return error.WriterError;
    }
};

