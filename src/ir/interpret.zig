// This file will probably disappear when a good enough bytecode gets up to speed
const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Writer = std.fs.File.Writer;

const IrError = @import("errors.zig").IrError;
const Function = @import("nodes/decl.zig").Function;
const Stmt = @import("nodes/statement.zig").Stmt;
const Program = @import("nodes/program.zig").Program;
const Value = @import("nodes/value.zig").Value;
const Decl = @import("nodes/decl.zig").Decl;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;

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

    pub fn init(allocator: Allocator, writer: Writer, program: Program) !Self {
        return .{
            .writer = writer,
            .program = program,
            .current_ele = null,
            .env = try ArrayList(Value).initCapacity(allocator, 50),
            .call_stack = ArrayList(Frame).init(allocator),
        };
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
                    try self.pushValue(Value.initUndef());
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
                self.current_ele = null;
                if (opt_val) |val| {
                    try self.pushValue(val);
                }
            },
        }
    }

    fn getFunction(self: Self, name: []const u8) IrError!Decl {
        // Just linear search for now
        for (self.program.decls) |decl| {
            if (std.mem.eql(u8, decl.name(), name)) {
                return decl;
            }
        }

        return error.NoSuchFunction;
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
        switch (value) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    return self.evalBool(try self.getAccessValOffset(offset));
                } else {
                    return error.ExpectedNumifiedAccess;
                }
            },
            .int, .float => return error.TypeError,
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

    fn evalUnaryOp(self: *Self, op: Value.UnaryOp) IrError!void {
        switch (op.kind) {
            .not => {
                self.evalValue(op.val.*) catch return error.OperandError;
                var boolVal = try self.evalBool(self.env.getLast());
                // This will always be boolean but recover nicely anyway
                switch (boolVal) {
                    .bool => |*b| b.* = @intFromBool(b.* != 1),
                    else => return error.InvalidBool,
                }
                try self.pushValue(boolVal);
            }
        }
    }

    // Pops two values off the stack, performs the given operator on them,
    // then pushes the result onto the stack.
    fn evalBinaryOp(self: *Self, op: Value.BinaryOp) IrError!void {
        // Special ops that don't just pop both values off and do a thing
        switch (op.kind) {
            .assign => {
                const index = switch (op.lhs.*) {
                    .access => |va| blk: {
                        if (va.offset) |offset| {
                            break :blk offset;
                        } else {
                            return error.ExpectedNumifiedAccess;
                        }
                    },
                    else => return error.InvalidLHSAssign,
                };
                self.evalValue(op.rhs.*) catch return error.OperandError;
                const rhs = self.env.getLast();
                self.env.items[self.getAbsoluteOffset(index)] = rhs;
                return;
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

        switch (op.kind) {
            .eq => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() == try rhs.asInt())
                );
            },
            .add => {
                try self.pushValue(
                    Value.initInt(try lhs.asInt() + try rhs.asInt())
                );
            },
            .sub => {
                try self.pushValue(
                    Value.initInt(try lhs.asInt() - try rhs.asInt())
                );
            },
            .mul => {
                try self.pushValue(
                    Value.initInt(try lhs.asInt() * try rhs.asInt())
                );
            },
            .div => {
                try self.pushValue(
                    Value.initInt(@divTrunc(try lhs.asInt(), try rhs.asInt()))
                );
            },
            .lt => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() < try rhs.asInt())
                );
            },
            .le => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() <= try rhs.asInt())
                );
            },
            .gt => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() > try rhs.asInt())
                );
            },
            .ge => {
                try self.pushValue(
                    Value.initBool(try lhs.asInt() >= try rhs.asInt())
                );
            },
            else => unreachable,
        }
    }

    fn evalValue(self: *Self, value: Value) IrError!void {
        switch (value) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    try self.evalValue(try self.getAccessValOffset(offset));
                } else {
                    return error.ExpectedNumifiedAccess;
                }
            },
            .int => try self.pushValue(value),
            .float => try self.pushValue(value),
            .bool => try self.pushValue(value),
            .unary => |op| {
                try self.evalUnaryOp(op);
            },
            .binary => |op| {
                try self.evalBinaryOp(op);
            },
            .call => |call| {
                const ret = try self.evalCall(call);
                if (ret) |val| {
                    try self.pushValue(val);//self.evalValue(val);
                } else {
                    // Void function should get undef pushed. This should be
                    // done better.
                    try self.pushValue(Value.initUndef());
                }
            },
        }
    }

    fn evalCall(self: *Self, call: Value.FuncCall) IrError!?Value {
        for (call.arguments) |arg| {
            try self.evalValue(arg);
        }
        // TODO: We make assumptions here that should be analyzed, like a
        // return type actually means a value is returned.
        const func = try self.getFunction(call.function);
        try self.pushFrame();
        defer {
            const frame = self.popFrame();
            self.current_ele = frame.return_ele_index;
        }
        try self.interpretDecl(func);
        if (func.ty() != .none) {
            try self.evalValue(self.env.pop());
            const ret = self.env.pop();
            return ret;
        }

        return null;
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
        switch (value) {
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
            .float => |f| fmt.formatFloatDecimal(f, .{}, self.writer)
                    catch return error.WriterError,
            .bool => |b| self.writer.print("{}", .{b})
                    catch return error.WriterError,
            .call => |call| {
                self.writer.print("{s}(", .{call.function})
                        catch return error.WriterError;
                self.writer.writeAll(")")
                        catch return error.WriterError;
            },
            else => return error.InvalidValue,
        }

        self.writer.writeAll("\n") catch return error.WriterError;
    }
};

