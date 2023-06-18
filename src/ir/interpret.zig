// This file will probably disappear when a good enough bytecode gets up to speed
const std = @import("std");
const ArrayList = std.ArrayList;

const IrError = @import("errors.zig").IrError;
const Function = @import("nodes/decl.zig").Function;
const Stmt = @import("nodes/statement.zig").Stmt;
const Program = @import("nodes/program.zig").Program;
const Value = @import("nodes/value.zig").Value;

const Frame = struct {
    frame_env_begin: usize,
    return_bb_index: usize,
};

pub const Interpreter = struct {
    const Self = @This();

    program: Program,
    // The current basic block's index getting executed.
    // Will start and end as null.
    current_bb: ?usize,
    env: ArrayList(Value),
    call_stack: ArrayList(Frame),

    pub fn init(allocator: std.mem.Allocator, program: Program) !Self {
        return .{
            .program = program,
            .current_bb = null,
            .env = try ArrayList(Value).initCapacity(allocator, 50),
            .call_stack = ArrayList(Frame).init(allocator),
        };
    }

    pub fn interpret(self: *Self) IrError!void {
        var main_fn: ?Function = null;
        for (self.program.functions) |function| {
            if (std.mem.eql(u8, function.name, "main")) {
                main_fn = function;
                break;
            }
        } else {
            return error.NoMainFunction;
        }

        self.current_bb = if (main_fn.?.bbs.len > 0)
            0
        else
            null;

        try self.pushFrame();
        // For now ignore main return
        try self.interpretFn(main_fn.?);
        _ = self.popFrame();
    }

    pub fn interpretFn(self: *Self, function: Function) IrError!void {
        while (self.current_bb) |bb_idx| {
            // May go off edge
            if (function.bbs.len <= bb_idx) {
                return;
            }

            const bb = function.bbs[bb_idx];
            for (bb.statements) |stmt| {
                try self.evalStmt(stmt);
            }

            if (bb.terminator) |terminator| {
                try self.evalTerminator(terminator);
            } else {
                if (self.current_bb) |*current_bb| {
                    current_bb.* += 1;
                }
            }
        }
    }

    fn evalStmt(self: *Self, stmt: Stmt) IrError!void {
        switch (stmt) {
            .debug => |value| {
                try self.evalValue(value);
                std.debug.print("{}\n", .{self.env.pop()});
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
            .branch, .ret => return error.UnexpectedTerminator,
        }
    }

    fn evalTerminator(self: *Self, stmt: Stmt) IrError!void {
        switch (stmt) {
            .debug, .id, .value => return error.ExpectedTerminator,
            .branch => |branch| {
                const result = switch (branch) {
                    .conditional => |conditional| blk: {
                        try self.evalValue(conditional.lhs);
                        const lhs = self.env.pop();
                        // Evaluate the condition and abort if it's false
                        switch (conditional.kind) {
                            .zero => break :blk try lhs.asInt() == 0,
                            .eq => {
                                try self.evalValue(conditional.rhs.?);
                                const rhs = self.env.pop();
                                break :blk try lhs.asInt() == try rhs.asInt();
                            },
                            .less => {
                                try self.evalValue(conditional.rhs.?);
                                const rhs = self.env.pop();
                                break :blk try lhs.asInt() < try rhs.asInt();
                            },
                            .less_eq => {
                                try self.evalValue(conditional.rhs.?);
                                const rhs = self.env.pop();
                                break :blk try lhs.asInt() <= try rhs.asInt();
                            },
                            .greater => {
                                try self.evalValue(conditional.rhs.?);
                                const rhs = self.env.pop();
                                break :blk try lhs.asInt() > try rhs.asInt();
                            },
                            .greater_eq => {
                                try self.evalValue(conditional.rhs.?);
                                const rhs = self.env.pop();
                                break :blk try lhs.asInt() >= try rhs.asInt();
                            },
                        }
                    },
                    else => true,
                };

                if (!result) {
                    // Go to next basic block and return
                    if (self.current_bb) |*current_bb| {
                        current_bb.* += 1;
                    }
                }

                self.current_bb = branch.labelIndex();
            },
            .ret => |opt_val| {
                self.current_bb = null;
                if (opt_val) |val| {
                    try self.pushValue(val);
                }
            },
        }
    }

    fn getFunction(self: Self, name: []const u8) IrError!Function {
        // Just linear search for now
        for (self.program.functions) |function| {
            if (std.mem.eql(u8, function.name, name)) {
                return function;
            }
        }

        return error.NoSuchFunction;
    }

    fn getAbsoluteOffset(self: Self, offset: isize) usize {
        const index = @intCast(isize, self.call_stack.getLast().frame_env_begin) + offset;
        return @intCast(usize, index);
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
            .binary => {
                self.evalValue(value) catch return error.InvalidBool;
                const val = self.env.pop();
                return self.evalBool(val) catch return error.InvalidBool;
            },
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
            .@"and" => {
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
            .@"or" => {
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
            .fadd => {
                try self.pushValue(
                    Value.initFloat(try lhs.asFloat() + try rhs.asFloat())
                );
            },
            .fsub => {
                try self.pushValue(
                    Value.initFloat(try lhs.asFloat() - try rhs.asFloat())
                );
            },
            .fmul => {
                try self.pushValue(
                    Value.initFloat(try lhs.asFloat() * try rhs.asFloat())
                );
            },
            .fdiv => {
                try self.pushValue(
                    Value.initFloat(try lhs.asFloat() / try rhs.asFloat())
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
            .binary => |op| {
                try self.evalBinaryOp(op);
            },
            .call => |call| {
                const ret = try self.evalCall(call);
                if (ret) |val| {
                    return self.evalValue(val);
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
            self.current_bb = frame.return_bb_index;
        }
        try self.interpretFn(func);
        if (func.ret_ty != .none) {
            const ret = self.env.pop();
            return ret;
        }

        return null;
    }

    fn pushFrame(self: *Self) IrError!void {
        self.call_stack.append(.{
            .frame_env_begin = self.env.items.len,
            .return_bb_index = self.current_bb.?
        }) catch return error.FrameError;
    }

    fn popFrame(self: *Self) Frame {
        return self.call_stack.pop();
    }

    fn pushValue(self: *Self, value: Value) IrError!void {
        self.env.append(value) catch return error.StackError;
    }
};

