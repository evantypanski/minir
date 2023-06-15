const std = @import("std");
const ArrayList = std.ArrayList;

const FunctionBuilder = @import("ir/nodes/decl.zig").FunctionBuilder;
const BasicBlockBuilder = @import("ir/nodes/basic_block.zig").BasicBlockBuilder;
const ProgramBuilder = @import("ir/nodes/program.zig").ProgramBuilder;
const Instr = @import("ir/nodes/instruction.zig").Instr;
const Value = @import("ir/nodes/value.zig").Value;
const Disassembler = @import("ir/Disassembler.zig");
const numify = @import("ir/passes/numify.zig");
const visitor = @import("ir/passes/visitor.zig");
const Interpreter = @import("ir/interpret.zig").Interpreter;
const Lexer = @import("ir/lexer.zig").Lexer;
const Parser = @import("ir/parser.zig").Parser;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const file = try std.fs.cwd().openFile("example.min", .{ .mode = .read_only });
    const source = try file.readToEndAlloc(gpa, 10000);
    var lexer = Lexer.init(source);
    var parser = Parser.init(gpa, lexer);
    const program = try parser.parse();

    var disassembler = Disassembler {
        .writer = std.io.getStdErr().writer(),
        .program = program,
    };

    try disassembler.disassemble();
}

test {
    _ = @import("bytecode/interpret.zig");
    _ = @import("ir/nodes/program.zig");
}
