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
const Numify = @import("../ir/passes/numify.zig").Numify;
const visitor = @import("../ir/passes/visitor.zig");
const Lexer = @import("../ir/lexer.zig").Lexer;
const Parser = @import("../ir/parser.zig").Parser;
const PassManager = @import("../ir/passes/pass_manager.zig").PassManager;
const BlockifyPass = @import("../ir/passes/blockify.zig").BlockifyPass;
const Lower = @import("../ir/passes/lower.zig").Lower;
const Typecheck = @import("../ir/passes/typecheck.zig").Typecheck;
const ResolveBranches = @import("../ir/passes/resolve_branches.zig").ResolveBranches;
const SourceManager = @import("../ir/source_manager.zig").SourceManager;
const Diagnostics = @import("../ir/diagnostics_engine.zig").Diagnostics;
const Interpreter = @import("../bytecode/interpret.zig").Interpreter;
const Disassembler = @import("../bytecode/disassembler.zig").Disassembler;
const CommandLine = @import("command_line.zig").CommandLine;
const Options = @import("options.zig").Options;

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
    try self.drive_with_opts(cli_result);
}

pub fn drive_with_opts(self: Self, options: Options) !void {
    if (options == .none) {
        return;
    }

    const filename = options.filename() orelse return;

    var source_mgr = try SourceManager.initFilename(self.allocator, filename);
    const diag_engine = Diagnostics.init(source_mgr);
    const lexer = Lexer.init(source_mgr);
    var parser = Parser.init(self.allocator, lexer, diag_engine);
    var program = try parser.parse();
    defer program.deinit(self.allocator);

    var pass_manager = PassManager.init(self.allocator, &program, diag_engine);
    try pass_manager.get(Numify);
    try pass_manager.get(ResolveBranches);
    try pass_manager.get(Typecheck);

    switch (options) {
        .interpret => |config| {
            switch (config.interpreter_type) {
                .byte => {
                    const chunk = try pass_manager.get(Lower);
                    // TODO: Maybe deinit should be in the interpreter, but it
                    // doesn't allocate so eh.
                    defer chunk.deinit(self.allocator);

                    source_mgr.deinit();

                    var interp = Interpreter.init(chunk, self.out);
                    try interp.interpret();
                },
                .treewalk => {
                    var treewalk_interp = try TreewalkInterpreter.init(
                        self.allocator, self.out, program
                    );
                    try treewalk_interp.interpret();
                    source_mgr.deinit();
                    treewalk_interp.deinit();
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
            const chunk = try pass_manager.get(Lower);

            source_mgr.deinit();
            var disassembler = Disassembler.init(chunk, self.out);
            try disassembler.disassemble();
        },
        .none => {},
    }
}
