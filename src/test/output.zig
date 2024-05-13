//! Tests which ensure the output of bytecode and tree-walking interpreter
//! match the given expected value.

const std = @import("std");

const Driver = @import("../driver/Driver.zig");
const CommandLine = @import("../driver/command_line.zig").CommandLine;

// Runs the given test, where test is within the top-level 'tests/output' dir
fn run(name: []const u8) !void {
    const tests_dir = try std.fs.cwd().openDir("tests/output", .{});
    const test_file = try tests_dir.realpathAlloc(std.testing.allocator, name);
    defer std.testing.allocator.free(test_file);

    var outDir = std.testing.tmpDir(.{});
    defer outDir.cleanup();

    // Bytecode interpreter
    const byteOut = try outDir.dir.createFile("byte.out", .{ .read = true });

    const byteInterpret = CommandLine.InterpretConfig {
        .filename = test_file,
        .interpreter_type = .byte
    };
    const byteConfig = CommandLine.CommandLineResult {
        .interpret = byteInterpret
    };

    try Driver.init(std.testing.allocator, byteOut.writer())
            .drive_with_opts(byteConfig);
    try byteOut.seekTo(0);
    const byteResult = try byteOut.readToEndAlloc(std.testing.allocator, 1000);
    defer std.testing.allocator.free(byteResult);

    // Treewalk interpreter
    const treewalkOut =
            try outDir.dir.createFile("treewalk.out", .{ .read = true });
    const treewalkInterpret = CommandLine.InterpretConfig {
        .filename = test_file,
        .interpreter_type = .treewalk
    };
    const treeConfig = CommandLine.CommandLineResult {
        .interpret = treewalkInterpret
    };

    try Driver.init(std.testing.allocator, treewalkOut.writer())
            .drive_with_opts(treeConfig);
    try treewalkOut.seekTo(0);
    const treewalkResult =
            try treewalkOut.readToEndAlloc(std.testing.allocator, 1000);
    defer std.testing.allocator.free(treewalkResult);

    // Ensure the bytecode and treewalk interpreter are the same
    try std.testing.expectEqualStrings(byteResult, treewalkResult);

    // TODO: .expected file too?
}

test "output examples" {
    try run("minimal.min");
    try run("print.min");
}
