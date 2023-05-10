const std = @import("std");
const ArrayList = std.ArrayList;

const ir = @import("ir.zig");
const Disassembler = @import("Disassembler.zig");
const numify = @import("passes/numify.zig");
const visitor = @import("passes/visitor.zig");

const InterpError = error{
    OperandError,
    InvalidInt,
    InvalidFloat,
    InvalidBool,
    CannotEvaluateUndefined,
    VariableUndefined,
    InvalidLHSAssign,
    LabelNoIndex,
    TypeError,
    NoSuchFunction,
    ExpectedNumifiedAccess,
    CallError,
    ExpectedReturn,
    FrameError,
    StackError,
};

// Big!
const BigError = InterpError || ir.IrError;

const Frame = struct {
    frame_env_begin: usize,
    return_bb_index: usize,
};

const Interpreter = struct {
    const Self = @This();

    program: ir.Program,
    // The current basic block's index getting executed.
    // Will start and end as null.
    current_bb: ?usize,
    env: ArrayList(ir.Value),
    call_stack: ArrayList(Frame),

    pub fn init(allocator: std.mem.Allocator, program: ir.Program) !Self {
        return .{
            .program = program,
            .current_bb = null,
            .env = try ArrayList(ir.Value).initCapacity(allocator, 50),
            .call_stack = ArrayList(Frame).init(allocator),
        };
    }

    pub fn interpret(self: *Self) BigError!void {
        var main_fn: ?ir.Function = null;
        for (self.program.functions) |function| {
            if (std.mem.eql(u8, function.name, "main")) {
                main_fn = function;
                break;
            }
        } else {
            return error.NoMainFunction;
        }

        self.current_bb = if (main_fn.?.bbs.items.len > 0)
            0
        else
            null;

        // For now ignore main return
        try self.interpretFn(main_fn.?);
    }

    pub fn interpretFn(self: *Self, function: ir.Function) BigError!void {
        while (self.current_bb) |bb_idx| {
            // May go off edge
            if (function.bbs.items.len <= bb_idx) {
                return;
            }

            const bb = function.bbs.items[bb_idx];
            for (bb.instructions.items) |instr| {
                try self.evalInstr(instr);
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

    fn evalInstr(self: *Self, instr: ir.Instr) BigError!void {
        switch (instr) {
            .debug => |value| {
                try self.evalValue(value);
                std.debug.print("{}\n", .{self.env.pop()});
            },
            .id => |vd| {
                if (vd.val) |val| {
                    try self.evalValue(val);
                } else {
                    try self.pushValue(ir.Value.initUndef());
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

    fn evalTerminator(self: *Self, instr: ir.Instr) BigError!void {
        switch (instr) {
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

    fn getFunction(self: Self, name: []const u8) BigError!ir.Function {
        // Just linear search for now
        for (self.program.functions) |function| {
            if (std.mem.eql(u8, function.name, name)) {
                return function;
            }
        }

        return error.NoSuchFunction;
    }

    // Gets the current runtime value from an offset
    fn getAccessValOffset(self: Self, offset: usize) BigError!ir.Value {
        // TODO: Functions will need to use actual offset from stack spot
        return self.env.items[offset];
    }

    // Evaluates a given value as a boolean, or returns an error if it
    // cannot be coerced.
    fn evalBool(self: *Self, value: ir.Value) BigError!ir.Value {
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
                const func = try self.getFunction(call.function);
                if (func.ret_ty != .boolean) {
                    return error.TypeError;
                }
                try self.pushFrame();
                defer {
                    const frame = self.popFrame();
                    self.current_bb = frame.return_bb_index;
                }
                try self.interpretFn(func);
                // TODO: We don't yet ensure we actually returned a value.
                const ret = self.env.pop();
                return ret;
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
    fn evalBinaryOp(self: *Self, op: ir.Value.BinaryOp) BigError!void {
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
                self.env.items[index] = rhs;
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
                    ir.Value.initInt(try lhs.asInt() + try rhs.asInt())
                );
            },
            .sub => {
                try self.pushValue(
                    ir.Value.initInt(try lhs.asInt() - try rhs.asInt())
                );
            },
            .mul => {
                try self.pushValue(
                    ir.Value.initInt(try lhs.asInt() * try rhs.asInt())
                );
            },
            .div => {
                try self.pushValue(
                    ir.Value.initInt(@divTrunc(try lhs.asInt(), try rhs.asInt()))
                );
            },
            .fadd => {
                try self.pushValue(
                    ir.Value.initFloat(try lhs.asFloat() + try rhs.asFloat())
                );
            },
            .fsub => {
                try self.pushValue(
                    ir.Value.initFloat(try lhs.asFloat() - try rhs.asFloat())
                );
            },
            .fmul => {
                try self.pushValue(
                    ir.Value.initFloat(try lhs.asFloat() * try rhs.asFloat())
                );
            },
            .fdiv => {
                try self.pushValue(
                    ir.Value.initFloat(try lhs.asFloat() / try rhs.asFloat())
                );
            },
            .lt => {
                try self.pushValue(
                    ir.Value.initBool(try lhs.asInt() < try rhs.asInt())
                );
            },
            .le => {
                try self.pushValue(
                    ir.Value.initBool(try lhs.asInt() <= try rhs.asInt())
                );
            },
            .gt => {
                try self.pushValue(
                    ir.Value.initBool(try lhs.asInt() > try rhs.asInt())
                );
            },
            .ge => {
                try self.pushValue(
                    ir.Value.initBool(try lhs.asInt() >= try rhs.asInt())
                );
            },
            else => unreachable,
        }
    }

    fn evalValue(self: *Self, value: ir.Value) BigError!void {
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
                const func = try self.getFunction(call.function);
                try self.pushFrame();
                defer {
                    const frame = self.popFrame();
                    self.current_bb = frame.return_bb_index;
                }
                try self.interpretFn(func);
            },
        }
    }

    fn pushFrame(self: *Self) BigError!void {
        self.call_stack.append(.{
            .frame_env_begin = self.env.items.len,
            // Calls are terminators so add 1
            .return_bb_index = self.current_bb.? + 1
        }) catch return error.FrameError;
    }

    fn popFrame(self: *Self) Frame {
        return self.call_stack.pop();
    }

    fn pushValue(self: *Self, value: ir.Value) BigError!void {
        self.env.append(value) catch return error.StackError;
    }
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    var func_builder = ir.FunctionBuilder.init(gpa, "main");

    var bb1_builder = ir.BasicBlockBuilder.init(gpa);
    bb1_builder.setLabel("bb1");
    try bb1_builder.addInstruction(
        ir.Instr {
            .id = .{
                .name = "hi",
                .val = .{ .int = 99 },
                .ty = .int,
            }
        }
    );
    var hi_access = ir.Value.initAccessName("hi");
    try bb1_builder.addInstruction(ir.Instr{ .debug = hi_access });
    try bb1_builder.addInstruction(.{ .debug = ir.Value.initCall("f") });
    //try bb1_builder.setTerminator(
        //ir.Instr{ .call = .{ .function = "f" } }
    //);
    try func_builder.addBasicBlock(bb1_builder.build());

    var bb2_builder = ir.BasicBlockBuilder.init(gpa);
    bb2_builder.setLabel("bb2");
    var val1 = ir.Value{ .int = 50 };
    try bb2_builder.addInstruction(ir.Instr{ .debug = val1 });
    try bb2_builder.setTerminator(.{.ret = null});
    try func_builder.addBasicBlock(bb2_builder.build());

    const func = try func_builder.build();

    var bb4_builder = ir.BasicBlockBuilder.init(gpa);
    bb4_builder.setLabel("bb4");
    try bb4_builder.setTerminator(.{.ret = ir.Value.initInt(5)});
    var func2_builder = ir.FunctionBuilder.init(gpa, "f");
    func2_builder.setReturnType(.int);
    try func2_builder.addBasicBlock(bb4_builder.build());
    const func2 = try func2_builder.build();
    var prog_builder = ir.ProgramBuilder.init(gpa);
    try prog_builder.addFunction(func);
    try prog_builder.addFunction(func2);
    var program = try prog_builder.build();
    const disassembler = Disassembler{
        .writer = std.io.getStdOut().writer(),
        .program = program,
    };

    // Numify!
    var numify_pass = numify.init(gpa);
    const numify_visitor = numify.NumifyVisitor;
    // Wow this is ugly.
    try numify_visitor.visitProgram(numify_visitor, &numify_pass, &program);

    try disassembler.disassemble();
    var interpreter = try Interpreter.init(gpa, program);
    try interpreter.interpret();
}
