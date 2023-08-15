const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Writer = std.fs.File.Writer;

const FunctionBuilder = @import("../ir/nodes/decl.zig").FunctionBuilder;
const BasicBlockBuilder = @import("../ir/nodes/basic_block.zig").BasicBlockBuilder;
const ProgramBuilder = @import("../ir/nodes/program.zig").ProgramBuilder;
const Stmt = @import("../ir/nodes/statement.zig").Stmt;
const Value = @import("../ir/nodes/value.zig").Value;
const Formatter = @import("../ir/disassembler.zig").Disassembler;
const TreewalkInterpreter = @import("../ir/interpret.zig").Interpreter;
const Numify = @import("../ir/passes/numify.zig");
const visitor = @import("../ir/passes/visitor.zig");
const Lexer = @import("../ir/lexer.zig").Lexer;
const Parser = @import("../ir/parser.zig").Parser;
const BlockifyPass = @import("../ir/passes/blockify.zig").BlockifyPass;
const Lowerer = @import("../ir/passes/lower.zig").Lowerer;
const SourceManager = @import("../ir/source_manager.zig").SourceManager;
const Diagnostics = @import("../ir/diagnostics_engine.zig").Diagnostics;
const Interpreter = @import("../bytecode/interpret.zig").Interpreter;
const Disassembler = @import("../bytecode/disassembler.zig").Disassembler;
const CommandLine = @import("command_line.zig").CommandLine;

const Self = @This();

allocator: Allocator,
out: Writer,

pub fn init(allocator: Allocator, out: Writer) Self {
    return .{
        .allocator = allocator,
        .out = out,
    };
}

pub fn drive(self: Self) !void {
    const cli = try CommandLine.init(self.allocator, self.out);
    const cli_result = try cli.parse();
    defer cli.deinit();

    if (cli_result == .none) {
        return;
    }

    const filename = cli_result.filename() orelse return;

    var source_mgr = try SourceManager.initFilename(self.allocator, filename);
    const diag_engine = Diagnostics.init(source_mgr);
    var lexer = Lexer.init(source_mgr);
    var parser = Parser.init(self.allocator, lexer, diag_engine);
    var program = try parser.parse();
    var numifyVisitor = Numify.init(self.allocator);
    try numifyVisitor.execute(&program);

    switch (cli_result) {
        .interpret => |config| {
            switch (config.interpreter_type) {
                .byte => {
                    var lowerer = Lowerer.init(self.allocator);
                    try lowerer.execute(&program);
                    const chunk = try lowerer.builder.build();

                    source_mgr.deinit();

                    var interp = Interpreter.init(chunk, self.out);
                    try interp.interpret();
                },
                .treewalk => {
                    var treewalk_interp = try TreewalkInterpreter.init(
                        self.allocator, self.out, program
                    );
                    try treewalk_interp.interpret();
                },
            }
        },
        .fmt => {
            const formatter = Formatter {
                .writer = self.out,
                .program = program,
            };

            try formatter.disassemble();
        },
        .dump => {
            var lowerer = Lowerer.init(self.allocator);
            try lowerer.execute(&program);

            source_mgr.deinit();

            const chunk = try lowerer.builder.build();
            var disassembler = Disassembler.init(chunk, self.out);
            try disassembler.disassemble();
        },
        .none => return,
    }

}
