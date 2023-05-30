const std = @import("std");
const ArrayList = std.ArrayList;

//const FunctionBuilder = @import("ir/nodes/function.zig").FunctionBuilder;
//const BasicBlockBuilder = @import("ir/nodes/basic_block.zig").BasicBlockBuilder;
//const ProgramBuilder = @import("ir/nodes/program.zig").ProgramBuilder;
//const Instr = @import("ir/nodes/instruction.zig").Instr;
//const Value = @import("ir/nodes/value.zig").Value;
//const Disassembler = @import("ir/Disassembler.zig");
//const numify = @import("ir/passes/numify.zig");
//const visitor = @import("ir/passes/visitor.zig");
//const Interpreter = @import("ir/interpret.zig").Interpreter;

const Interpreter = @import("bytecode/interpret.zig").Interpreter;
const Disassembler = @import("bytecode/disassembler.zig").Disassembler;
const Verifier = @import("bytecode/verify.zig").Verifier;
const ChunkBuilder = @import("bytecode/chunk.zig").ChunkBuilder;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var builder = ChunkBuilder.init(gpa);
    const begin = try builder.addValue(.{ .int = 0 });
    const five = try builder.addValue(.{ .int = 5 });
    const one = try builder.addValue(.{ .int = 1 });
    const forty_two = try builder.addValue(.{ .int = 42 });

    // alloc offset 0
    try builder.addOp(.alloc);
    try builder.addOp(.constant);
    try builder.addByte(begin);
    // Set offset 0 aka what we allocd
    try builder.addOp(.set);
    try builder.addByte(0);

    const loop_beg = builder.currentByte();

    try builder.addOp(.get);
    try builder.addByte(0);
    try builder.addOp(.debug);

    // Subtract one. That's a lot.
    try builder.addOp(.get);
    try builder.addByte(0);
    try builder.addOp(.constant);
    try builder.addByte(one);
    try builder.addOp(.add);
    try builder.addOp(.set);
    try builder.addByte(0);

    // Is it greater than 0
    try builder.addOp(.get);
    try builder.addByte(0);
    try builder.addOp(.constant);
    try builder.addByte(five);
    try builder.addOp(.gt);
    try builder.addOp(.jmpf);
    // Since this is two off from the end
    const loop_end_minus_two = builder.currentByte();
    try builder.addShort(@intCast(i16, loop_beg) - @intCast(i16, loop_end_minus_two) - 2);

    // Out of loop
    try builder.addOp(.constant);
    try builder.addByte(forty_two);
    try builder.addOp(.debug);
    try builder.addOp(.ret);

    var chunk = try builder.build();

    std.debug.print("\nVerifying...\n", .{});
    var verifier = Verifier.init(chunk);
    if (verifier.verify()) {
        std.debug.print("Verification succeeded!\n", .{});
    } else {
        std.debug.print("Verification failed!\n", .{});
        return;
    }

    std.debug.print("\nDisassembling...\n", .{});
    var disassembler = Disassembler.init(std.io.getStdOut().writer(), chunk);
    try disassembler.disassemble();

    std.debug.print("\nInterpreting...\n", .{});
    var interpreter = Interpreter.init(chunk, std.io.getStdOut().writer());
    try interpreter.interpret();

    chunk.deinit(gpa);

    // Commented out because it may be used later. definitely good practice :)
    //    var func_builder = FunctionBuilder.init(gpa, "main");
    //
    //    var bb1_builder = BasicBlockBuilder.init(gpa);
    //    bb1_builder.setLabel("bb1");
    //    try bb1_builder.addInstruction(
    //        Instr {
    //            .id = .{
    //                .name = "hi",
    //                .val = .{ .int = 99 },
    //                .ty = .int,
    //            }
    //        }
    //    );
    //    var hi_access = Value.initAccessName("hi");
    //    var params = std.ArrayList(Value).init(gpa);
    //    try params.append(hi_access);
    //    try params.append(Value{ .int = 50 });
    //    try bb1_builder.addInstruction(.{ .debug = Value.initCall("f", try params.toOwnedSlice()) });
    //    try func_builder.addBasicBlock(try bb1_builder.build());
    //
    //    var bb2_builder = BasicBlockBuilder.init(gpa);
    //    bb2_builder.setLabel("bb2");
    //    var val1 = Value{ .int = 50 };
    //    try bb2_builder.addInstruction(Instr{ .debug = val1 });
    //    try bb2_builder.setTerminator(.{.ret = null});
    //    try func_builder.addBasicBlock(try bb2_builder.build());
    //
    //    const func = try func_builder.build();
    //
    //    var bb4_builder = BasicBlockBuilder.init(gpa);
    //    bb4_builder.setLabel("bb4");
    //    try bb4_builder.setTerminator(.{.ret = Value.initInt(5)});
    //    var func2_builder = FunctionBuilder.init(gpa, "f");
    //    func2_builder.setReturnType(.int);
    //    try func2_builder.addParam(.{
    //                .name = "par1",
    //                .val = null,
    //                .ty = .int,
    //            });
    //    try func2_builder.addParam(.{
    //                .name = "par2",
    //                .val = null,
    //                .ty = .int,
    //            });
    //    var par1_access = Value.initAccessName("par1");
    //    try bb4_builder.addInstruction(Instr{ .debug = par1_access });
    //    var par2_access = Value.initAccessName("par2");
    //    try bb4_builder.addInstruction(Instr{ .debug = par2_access });
    //    try func2_builder.addBasicBlock(try bb4_builder.build());
    //    const func2 = try func2_builder.build();
    //    var prog_builder = ProgramBuilder.init(gpa);
    //    try prog_builder.addFunction(func);
    //    try prog_builder.addFunction(func2);
    //
    //    var program = try prog_builder.build();
    //    defer program.deinit(gpa);
    //
    //    const disassembler = Disassembler{
    //        .writer = std.io.getStdOut().writer(),
    //        .program = program,
    //    };
    //
    //    // Numify!
    //    var numify_pass = numify.init(gpa);
    //    const numify_visitor = numify.NumifyVisitor;
    //    // Wow this is ugly.
    //    try numify_visitor.visitProgram(numify_visitor, &numify_pass, &program);
    //
    //    try disassembler.disassemble();
    //    var interpreter = try Interpreter.init(gpa, program);
    //    try interpreter.interpret();
}

test {
    _ = @import("bytecode/interpret.zig");
    _ = @import("ir/nodes/program.zig");
}
