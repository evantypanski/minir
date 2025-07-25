const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AnyWriter = std.io.AnyWriter;

const FunctionBuilder = @import("../ir/nodes/decl.zig").FunctionBuilder;
const BasicBlockBuilder = @import("../ir/nodes/basic_block.zig").BasicBlockBuilder;
const ProgramBuilder = @import("../ir/nodes/program.zig").ProgramBuilder;
const Stmt = @import("../ir/nodes/statement.zig").Stmt;
const Value = @import("../ir/nodes/value.zig").Value;
const Formatter = @import("../ir/dump/disassembler.zig").Disassembler;
const JSONifier = @import("../ir/dump/json.zig").JSONifier;
const TreewalkInterpreter = @import("../ir/interpret.zig").Interpreter;
const Numify = @import("../ir/passes/numify.zig").Numify;
const Blockify = @import("../ir/passes/blockify.zig").Blockify;
const Lexer = @import("../ir/lexer.zig").Lexer;
const Parser = @import("../ir/parser.zig").Parser;
const PassManager = @import("../ir/passes/util/pass_manager.zig").PassManager;
const Lower = @import("../ir/passes/lower.zig").Lower;
const Typecheck = @import("../ir/passes/typecheck.zig").Typecheck;
const ResolveBranches = @import("../ir/passes/resolve_branches.zig").ResolveBranches;
const ResolveCalls = @import("../ir/passes/resolve_calls.zig").ResolveCalls;
const SourceManager = @import("../ir/source_manager.zig").SourceManager;
const Diagnostics = @import("../ir/diagnostics_engine.zig").Diagnostics;
const Interpreter = @import("../bytecode/interpret.zig").Interpreter;
const Disassembler = @import("../bytecode/disassembler.zig").Disassembler;
const Chunk = @import("../bytecode/chunk.zig").Chunk;
const CommandLine = @import("command_line.zig").CommandLine;
const Options = @import("options.zig").Options;

const Self = @This();
pub const default_passes = &[_]type{ Numify, ResolveBranches, ResolveCalls, Typecheck, Blockify };

allocator: Allocator,
out: AnyWriter,

pub fn init(allocator: Allocator, out: AnyWriter) Self {
    return .{
        .allocator = allocator,
        .out = out,
    };
}

/// Drives using the CLI arguments; the default entry-point
pub fn drive(self: Self) !void {
    const cli = try CommandLine.init(self.allocator, self.out);
    defer cli.deinit();
    const cli_result = try cli.parse();
    // Run through extra passes version because it auto-adds default passes
    try self.driveWithExtraPasses(cli_result, &[_]type{});
}

/// Drives with the options and default passes with the extra passes coming after the default
pub fn driveWithExtraPasses(self: Self, options: Options, extra_passes: []const type) !void {
    try self.driveWithOpts(options, default_passes ++ extra_passes);
}

/// Drives with the given options
pub fn driveWithOpts(self: Self, options: Options, passes: []const type) !void {
    if (options == .none) {
        return;
    }

    const filename = options.filename() orelse return;

    // TODO: Redo this function so that this isn't necessary. It's needed
    // here because a binary interpreter type shouldn't treat the file
    // as minir, instead it's just bytecode.
    if (options == .interpret) {
        if (options.interpret.interpreter_type == .binary) {
            try self.interpretBinary(filename);
            return;
        }
    }

    var source_mgr = try SourceManager.initFilename(self.allocator, filename);
    const diag_engine = Diagnostics.init(source_mgr);
    const lexer = try Lexer.init(self.allocator, source_mgr);
    var parser = Parser.init(self.allocator, lexer, diag_engine);
    var program = try parser.parse();
    defer program.deinit(self.allocator);
    lexer.deinit();

    var pass_manager = PassManager.init(self.allocator, &program, diag_engine);
    inline for (passes) |pass| {
        // Passes that are run in this step cannot be providers since we cannot get the result
        if (pass.pass_kind == .provider) {
            @compileError("Providers cannot be a provided pass: " ++
                @typeName(pass));
        }
        try pass_manager.get(pass);
    }

    switch (options) {
        .interpret => |config| {
            switch (config.interpreter_type) {
                .byte => {
                    const chunk = try pass_manager.get(Lower);
                    defer chunk.deinit(self.allocator);

                    source_mgr.deinit();

                    var interp = Interpreter.init(chunk, self.out);
                    try interp.interpret();
                },
                .treewalk => {
                    var treewalk_interp = try TreewalkInterpreter.init(self.allocator, self.out, program);
                    try treewalk_interp.interpret();
                    source_mgr.deinit();
                    treewalk_interp.deinit();
                },
                .binary => unreachable,
            }
        },
        .fmt => {
            const formatter = Formatter{
                .writer = self.out,
                .program = program,
            };

            try formatter.disassemble();
        },
        .dump => |config| {
            // Do dumps for formats on minir (not bytecode)
            switch (config.format) {
                .json => {
                    var jsonifier = JSONifier{
                        .writer = self.out,
                        .program = program,
                    };
                    try jsonifier.disassemble();
                    source_mgr.deinit();
                    return;
                },
                else => {},
            }
            const chunk = try pass_manager.get(Lower);
            defer chunk.deinit(self.allocator);

            source_mgr.deinit();
            switch (config.format) {
                .binary => {
                    const bytes = try chunk.bytesAlloc(self.allocator);
                    defer self.allocator.free(bytes);
                    try self.out.writeAll(bytes);
                },
                .debug => {
                    var disassembler = Disassembler.init(chunk, self.out);
                    try disassembler.disassemble();
                },
                else => unreachable,
            }
        },
        .none => {},
    }
}

fn interpretBinary(self: Self, filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    const source = try file.readToEndAlloc(self.allocator, std.math.maxInt(u32));
    defer self.allocator.free(source);

    const chunk = try Chunk.parse(source, self.allocator);
    defer chunk.deinit(self.allocator);

    var interp = Interpreter.init(chunk, self.out);
    try interp.interpret();
}
