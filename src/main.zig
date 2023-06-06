const std = @import("std");
const ArrayList = std.ArrayList;

const FunctionBuilder = @import("ir/nodes/function.zig").FunctionBuilder;
const BasicBlockBuilder = @import("ir/nodes/basic_block.zig").BasicBlockBuilder;
const ProgramBuilder = @import("ir/nodes/program.zig").ProgramBuilder;
const Instr = @import("ir/nodes/instruction.zig").Instr;
const Value = @import("ir/nodes/value.zig").Value;
const Disassembler = @import("ir/Disassembler.zig");
const numify = @import("ir/passes/numify.zig");
const visitor = @import("ir/passes/visitor.zig");
const Interpreter = @import("ir/interpret.zig").Interpreter;
const Lexer = @import("ir/lexer.zig").Lexer;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const file = try std.fs.cwd().openFile("tinyexample.min", .{ .mode = .read_only });
    const source = try file.readToEndAlloc(gpa, 10000);
    var lexer = Lexer.init(source);
    var tok = lexer.lex();
    while (tok.ty != .EOF) : (tok = lexer.lex()) {
        std.debug.print("{}\n", .{tok});
    }
}

test {
    _ = @import("bytecode/interpret.zig");
    _ = @import("ir/nodes/program.zig");
}
