//! Tests for running transformations and comparing the output.

const std = @import("std");

const Program = @import("../nodes/program.zig").Program;
const SourceManager = @import("../source_manager.zig").SourceManager;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;
const Disassembler = @import("../disassembler.zig").Disassembler;
const Lexer = @import("../lexer.zig").Lexer;
const Parser = @import("../parser.zig").Parser;
const PassManager = @import("../passes/pass_manager.zig").PassManager;
const BlockifyPass = @import("../passes/blockify.zig").BlockifyPass;
const Blockify = @import("../passes/blockify.zig").Blockify;
const FoldConstantsPass = @import("../passes/fold_constants.zig").FoldConstantsPass;

fn parseProgramFromString(str: []const u8) !Program {
    var source_mgr = try SourceManager.init(std.testing.allocator, str, false);
    defer source_mgr.deinit();
    const diag_engine = Diagnostics.init(source_mgr);
    return parseProgram(source_mgr, diag_engine);
}

fn parseProgram(source_mgr: SourceManager, diag_engine: Diagnostics) !Program {
    const lexer = Lexer.init(source_mgr);
    var parser = Parser.init(std.testing.allocator, lexer, diag_engine);
    return try parser.parse();
}

fn expectDisassembled(program: Program, expected: []const u8) !void {
    var tmpdir = std.testing.tmpDir(.{});
    defer tmpdir.cleanup();
    var outFile = try tmpdir.dir.createFile("out", .{});

    const disassembler = Disassembler {
        .writer = outFile.writer(),
        .program = program,
    };
    try disassembler.disassemble();
    outFile.close();

    var outFileRead = try tmpdir.dir.openFile("out", .{.mode = .read_only});
    const disassembled = try outFileRead.readToEndAlloc(std.testing.allocator, 10000);
    defer std.testing.allocator.free(disassembled);

    try std.testing.expectStringStartsWith(disassembled, expected);
}

test "Test no passes" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 42
        \\}
        ;

    var start = try parseProgramFromString(begin_str);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  let i: int = 42
        \\}
    );
}

test "Test simple blockify" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 42
        \\}
        ;

    var start = try parseProgramFromString(begin_str);
    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.run(BlockifyPass);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  {
        \\    let i: int = 42
        \\  }
        \\}
    );
}

test "Test blockify with jump" {
    const begin_str =
        \\func main() -> none {
        \\  @label
        \\  let i: int = 42
        \\  br label
        \\  let j: int = 420
        \\}
        ;

    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var start = try parseProgram(source_mgr, diag);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.run(BlockifyPass);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  @label {
        \\    let i: int = 42
        \\    br label
        \\  }
        \\  {
        \\    let j: int = 420
        \\  }
        \\}
    );
}

test "Test blockify with lazy Pass" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 42
        \\}
        ;

    var start = try parseProgramFromString(begin_str);
    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.get(Blockify, BlockifyPass);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  {
        \\    let i: int = 42
        \\  }
        \\}
    );
}

test "Test simple constant folding" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 40 + 2
        \\}
        ;

    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var start = try parseProgram(source_mgr, diag);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.run(FoldConstantsPass);
    defer start.deinit(std.testing.allocator);

    // Parentheses be damned
    try expectDisassembled(start,
        \\func main() -> none {
        \\  let i: int = 42
        \\}
    );
}
