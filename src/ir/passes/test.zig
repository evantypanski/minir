//! Tests for running transformations and comparing the output.

const std = @import("std");

const Program = @import("../nodes/program.zig").Program;
const SourceManager = @import("../source_manager.zig").SourceManager;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;
const Disassembler = @import("../dump/disassembler.zig").Disassembler;
const Lexer = @import("../lexer.zig").Lexer;
const Parser = @import("../parser.zig").Parser;
const PassManager = @import("util/pass_manager.zig").PassManager;
const Blockify = @import("blockify.zig").Blockify;
const FoldConstants = @import("fold_constants.zig").FoldConstants;

fn parseProgramFromString(str: []const u8) !Program {
    var source_mgr = try SourceManager.init(std.testing.allocator, str, false);
    defer source_mgr.deinit();
    const diag_engine = Diagnostics.init(source_mgr);
    return parseProgram(source_mgr, diag_engine);
}

fn parseProgram(source_mgr: SourceManager, diag_engine: Diagnostics) !Program {
    const lexer = try Lexer.init(std.testing.allocator, source_mgr);
    defer lexer.deinit();
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
    const disassembled = try outFileRead.readToEndAlloc(std.testing.allocator, std.math.maxInt(u32));
    defer std.testing.allocator.free(disassembled);

    try std.testing.expectStringStartsWith(disassembled, expected);
}

test "Test no passes" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 42;
        \\}
        ;

    var start = try parseProgramFromString(begin_str);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  let i: int = 42;
        \\}
    );
}

test "Test simple blockify" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 42;
        \\}
        ;

    var start = try parseProgramFromString(begin_str);
    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.get(Blockify);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  {
        \\    let i: int = 42;
        \\  }
        \\}
    );
}

test "Test blockify with jump" {
    const begin_str =
        \\func main() -> none {
        \\  @label
        \\  let i: int = 42;
        \\  br label;
        \\  let j: int = 420;
        \\}
        ;

    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var start = try parseProgram(source_mgr, diag);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.get(Blockify);
    defer start.deinit(std.testing.allocator);

    try expectDisassembled(start,
        \\func main() -> none {
        \\  @label {
        \\    let i: int = 42;
        \\    br label;
        \\  }
        \\  {
        \\    let j: int = 420;
        \\  }
        \\}
    );
}

test "Test simple constant folding" {
    const begin_str =
        \\func main() -> none {
        \\  let i: int = 40 + 2;
        \\}
        ;

    var source_mgr = try SourceManager.init(std.testing.allocator, begin_str, false);
    defer source_mgr.deinit();
    const diag = Diagnostics.init(source_mgr);
    var start = try parseProgram(source_mgr, diag);
    var pass_manager = PassManager.init(std.testing.allocator, &start, diag);
    try pass_manager.get(FoldConstants);
    defer start.deinit(std.testing.allocator);

    // Parentheses be damned
    try expectDisassembled(start,
        \\func main() -> none {
        \\  let i: int = 42;
        \\}
    );
}
