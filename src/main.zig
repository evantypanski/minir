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
    UnknownLabel,
    // Just catch all the type errors with this for now
    TypeError,
    NoSuchFunction,
    NoAccessValue,
    IrError,
};
const Interpreter = struct {
    const Self = @This();

    program: ir.Program,
    // The current basic block's index getting executed.
    // Will start and end as null.
    current_bb: ?usize,
    env: ArrayList(ir.Value),
    // Var name to spot on stack
    // TODO: This will be removed for call frames etc. so that variables
    // can be redefed with same name in different functions
    map: std.StringHashMap(usize),
    // TODO: This will be a call stack
    current_function: ?ir.Function,

    pub fn init(allocator: std.mem.Allocator, program: ir.Program) !Self {
        var main_fn: ?ir.Function = null;
        for (program.functions) |function| {
            if (std.mem.eql(u8, function.name, "main")) {
                main_fn = function;
                break;
            }
        } else {
            return error.NoMainFunction;
        }

        return .{
            .program = program,
            .current_bb = null,
            .env = try ArrayList(ir.Value).initCapacity(allocator, 50),
            .map = std.StringHashMap(usize).init(allocator),
            .current_function = main_fn,
        };
    }

    pub fn interpret(self: *Self) !void {
        self.current_bb = if (self.current_function.?.bbs.items.len > 0)
            0
        else
            null;

        while (self.current_bb) |bb_idx| {
            const function = self.current_function orelse return;
            // May go off edge
            if (function.bbs.items.len <= bb_idx) {
                break;
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

    fn evalInstr(self: *Self, instr: ir.Instr) !void {
        switch (instr) {
            .debug => |value| {
                try self.evalValue(value);
                std.debug.print("{}\n", .{self.env.pop()});
            },
            .id => |vd| {
                if (vd.val) |val| {
                    try self.evalValue(val);
                } else {
                    try self.env.append(ir.Value.initUndef());
                }

                try self.map.put(vd.name, self.env.items.len - 1);
            },
            .call, .branch, .ret => return error.UnexpectedTerminator,
        }
    }

    fn evalTerminator(self: *Self, instr: ir.Instr) !void {
        switch (instr) {
            .debug, .id => return error.ExpectedTerminator,
            .call => |call| {
                const func = try self.getFunction(call.function);
                self.current_function = func;
                self.current_bb = 0;
            },
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
                    return;
                }

                self.current_bb =
                    self.current_function.?.map.get(branch.labelName())
                            orelse return error.UnknownLabel;
            },
            .ret => self.current_bb = null,
        }
    }

    fn getFunction(self: Self, name: []const u8) !ir.Function {
        // Just linear search for now
        for (self.program.functions) |function| {
            if (std.mem.eql(u8, function.name, name)) {
                return function;
            }
        }

        return error.NoSuchFunction;
    }

    // Gets the current runtime value of a name
    fn getAccessVal(self: Self, name: []const u8) !ir.Value {
        const index = self.map.get(name) orelse return error.VariableUndefined;
        return self.env.items[index];
    }

    // Gets the current runtime value from an offset
    fn getAccessValOffset(self: Self, offset: usize) !ir.Value {
        // TODO: Functions will need to use actual offset from stack spot
        return self.env.items[offset];
    }

    // Evaluates a given value as a boolean, or returns an error if it
    // cannot be coerced.
    fn evalBool(self: *Self, value: ir.Value) InterpError!ir.Value {
        switch (value) {
            .undef => return error.CannotEvaluateUndefined,
            // TODO numify
            .access => |va| {
                if (va.offset) |offset| {
                    return self.evalBool(try self.getAccessValOffset(offset));
                } else if (va.name) |name| {
                    return self.evalBool(try self.getAccessVal(name));
                } else {
                    return error.NoAccessValue;
                }
            },
            .int, .float => return error.TypeError,
            .bool => return value,
            .binary => {
                self.evalValue(value) catch return error.InvalidBool;
                const val = self.env.pop();
                return self.evalBool(val) catch return error.InvalidBool;
            },
        }
    }

    fn evalInt(self: *Self, value: ir.Value) !ir.Value {
        switch (value) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    return self.evalInt(try self.getAccessValOffset(offset));
                } else if (va.name) |name| {
                    return self.evalInt(try self.getAccessVal(name));
                } else {
                    return error.NoAccessValue;
                }
            },
            .int => return value,
            .float, .bool => return error.TypeError,
            .binary => {
                try self.evalValue(value);
                const val = self.env.pop();
                return self.evalInt(val) catch error.InvalidInt;
            },
        }
    }

    fn evalFloat(self: *Self, value: ir.Value) !ir.Value {
        switch (value) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    return self.evalFloat(try self.getAccessValOffset(offset));
                } else if (va.name) |name| {
                    return self.evalFloat(try self.getAccessVal(name));
                } else {
                    return error.NoAccessValue;
                }
            },
            .int => |i| return ir.Value.initInt(@intToFloat(f32, i)),
            .float => return value,
            .bool => |b| return ir.Value.initFloat(@intToFloat(f32, b)),
            .binary => {
                try self.evalValue(value);
                const val = self.env.pop();
                return self.evalFloat(val) catch error.InvalidFloat;
            },
        }
    }

    // Pops two values off the stack, performs the given operator on them,
    // then pushes the result onto the stack.
    fn evalBinaryOp(self: *Self, op: ir.Value.BinaryOp) !void {
        // Special ops that don't just pop both values off and do a thing
        switch (op.kind) {
            .assign => {
                const index = switch (op.lhs.*) {
                    .access => |va| blk: {
                        if (va.offset) |offset| {
                            break :blk offset;
                        } else if (va.name) |name| {
                            break :blk self.map.get(name)
                                orelse return error.VariableUndefined;
                        } else {
                            return error.NoAccessValue;
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
                    try self.env.append(newLHS);
                    return;
                }

                self.evalValue(op.rhs.*) catch return error.OperandError;
                const newRHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                // Now append the result which is just the RHS
                try self.env.append(newRHS);
                return;
            },
            .@"or" => {
                self.evalValue(op.lhs.*) catch return error.OperandError;
                const newLHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                if (!try newLHS.asBool()) {
                    // Replace stack value with the new bool
                    try self.env.append(newLHS);
                    return;
                }

                self.evalValue(op.rhs.*) catch return error.OperandError;
                const newRHS = try self.evalBool(self.env.getLast());
                // No error so pop it
                _ = self.env.pop();
                // Now append the result which is just the RHS
                try self.env.append(newRHS);
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
                try self.env.append(
                    ir.Value.initInt(try lhs.asInt() + try rhs.asInt())
                );
            },
            .sub => {
                try self.env.append(
                    ir.Value.initInt(try lhs.asInt() - try rhs.asInt())
                );
            },
            .mul => {
                try self.env.append(
                    ir.Value.initInt(try lhs.asInt() * try rhs.asInt())
                );
            },
            .div => {
                try self.env.append(
                    ir.Value.initInt(@divTrunc(try lhs.asInt(), try rhs.asInt()))
                );
            },
            .fadd => {
                try self.env.append(
                    ir.Value.initFloat(try lhs.asFloat() + try rhs.asFloat())
                );
            },
            .fsub => {
                try self.env.append(
                    ir.Value.initFloat(try lhs.asFloat() - try rhs.asFloat())
                );
            },
            .fmul => {
                try self.env.append(
                    ir.Value.initFloat(try lhs.asFloat() * try rhs.asFloat())
                );
            },
            .fdiv => {
                try self.env.append(
                    ir.Value.initFloat(try lhs.asFloat() / try rhs.asFloat())
                );
            },
            .lt => {
                try self.env.append(
                    ir.Value.initBool(try lhs.asInt() < try rhs.asInt())
                );
            },
            .le => {
                try self.env.append(
                    ir.Value.initBool(try lhs.asInt() <= try rhs.asInt())
                );
            },
            .gt => {
                try self.env.append(
                    ir.Value.initBool(try lhs.asInt() > try rhs.asInt())
                );
            },
            .ge => {
                try self.env.append(
                    ir.Value.initBool(try lhs.asInt() >= try rhs.asInt())
                );
            },
            else => unreachable,
        }
    }

    fn evalValue(self: *Self, value: ir.Value) !void {
        switch (value) {
            .undef => return error.CannotEvaluateUndefined,
            .access => |va| {
                if (va.offset) |offset| {
                    try self.evalValue(try self.getAccessValOffset(offset));
                } else if (va.name) |name| {
                    try self.evalValue(try self.getAccessVal(name));
                } else {
                    return error.NoAccessValue;
                }
            },
            .int => try self.env.append(value),
            .float => try self.env.append(value),
            .bool => try self.env.append(value),
            .binary => |op| {
                try self.evalBinaryOp(op);
            },
        }
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
                .val = .{ .int = 99 }
            }
        }
    );
    var hi_access = ir.Value.initAccessName("hi");
    try bb1_builder.addInstruction(ir.Instr{ .debug = hi_access });
    try bb1_builder.setTerminator(
        ir.Instr{ .call = .{ .function = "f" } }
    );
    try func_builder.addBasicBlock(bb1_builder.build());

    var bb2_builder = ir.BasicBlockBuilder.init(gpa);
    bb2_builder.setLabel("bb2");
    var val1 = ir.Value{ .int = 50 };
    try bb2_builder.addInstruction(ir.Instr{ .debug = val1 });
    try bb2_builder.setTerminator(.ret);
    try func_builder.addBasicBlock(bb2_builder.build());

    var bb3_builder = ir.BasicBlockBuilder.init(gpa);
    bb3_builder.setLabel("bb3");
    var val2 = ir.Value{ .int = 42 };
    try bb3_builder.addInstruction(ir.Instr{ .debug = val2 });
    try bb3_builder.setTerminator(
        ir.Instr{ .branch =
            ir.Branch.initBinaryConditional("bb2", .greater, ir.Value.initInt(0),
                                            ir.Value.initInt(1))
        }
    );
    try func_builder.addBasicBlock(bb3_builder.build());

    const func = try func_builder.build();
    var func2_builder = ir.FunctionBuilder.init(gpa, "f");
    try func2_builder.addBasicBlock(bb3_builder.build());
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
    numify_visitor.visitProgram(numify_visitor, &numify_pass, &program);

    try disassembler.disassemble();
    var interpreter = try Interpreter.init(gpa, program);
    try interpreter.interpret();
}
