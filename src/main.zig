const std = @import("std");
const ArrayList = std.ArrayList;

const FunctionBuilder = @import("ir/nodes/decl.zig").FunctionBuilder;
const BasicBlockBuilder = @import("ir/nodes/basic_block.zig").BasicBlockBuilder;
const ProgramBuilder = @import("ir/nodes/program.zig").ProgramBuilder;
const Stmt = @import("ir/nodes/statement.zig").Stmt;
const Value = @import("ir/nodes/value.zig").Value;
const Disassembler = @import("ir/disassembler.zig").Disassembler;
const TreewalkInterpreter = @import("ir/interpret.zig").Interpreter;
const Numify = @import("ir/passes/numify.zig");
const visitor = @import("ir/passes/visitor.zig");
const Lexer = @import("ir/lexer.zig").Lexer;
const Parser = @import("ir/parser.zig").Parser;
const BlockifyPass = @import("ir/passes/blockify.zig").BlockifyPass;
const Lowerer = @import("ir/passes/lower.zig").Lowerer;
const SourceManager = @import("ir/source_manager.zig").SourceManager;
const Diagnostics = @import("ir/diagnostics_engine.zig").Diagnostics;
const Interpreter = @import("bytecode/interpret.zig").Interpreter;
const ByteDisassembler = @import("bytecode/disassembler.zig").Disassembler;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const stdout = std.io.getStdOut().writer();

    var source_mgr = try SourceManager.initFilename(gpa, "example.min");
    const diag_engine = Diagnostics.init(source_mgr);
    var lexer = Lexer.init(source_mgr);
    var parser = Parser.init(gpa, lexer, diag_engine);
    var program = try parser.parse();
    var numifyVisitor = Numify.init(gpa);
    try numifyVisitor.execute(&program);

    const disassembler = Disassembler { .writer = stdout, .program = program };
    try disassembler.disassemble();

    try stdout.print("Tree walking interpreter result:\n", .{});
    var treewalk_interp = try TreewalkInterpreter.init(gpa, stdout, program);
    try treewalk_interp.interpret();

    var lowerer = Lowerer.init(gpa);
    try lowerer.execute(&program);

    source_mgr.deinit();

    const chunk = try lowerer.builder.build();
    try stdout.print("Bytecode interpreter result:\n", .{});
    var interp = Interpreter.init(chunk, std.io.getStdOut().writer());
    try interp.interpret();
}

test {
    _ = @import("bytecode/interpret.zig");
    _ = @import("ir/nodes/program.zig");
    _ = @import("ir/passes/blockify.zig");
}
