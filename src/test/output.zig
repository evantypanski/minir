//! Tests which ensure the output of bytecode and tree-walking interpreter
//! match the given expected value.

const std = @import("std");

const Driver = @import("../driver/Driver.zig");
const Options = @import("../driver/options.zig").Options;
const InterpretConfig = @import("../driver/options.zig").InterpretConfig;

var outDir: std.testing.TmpDir = undefined;

// Runs the given test, where test is within the top-level 'tests/output' dir
fn run(comptime name: []const u8) !void {
    const tests_dir = try std.fs.cwd().openDir("tests/output", .{});
    const test_file = try tests_dir.realpathAlloc(std.testing.allocator, name);
    defer std.testing.allocator.free(test_file);

    // Bytecode interpreter
    const byte_result = try get_output(test_file, .byte);
    defer std.testing.allocator.free(byte_result);

    // Treewalk interpreter
    const treewalk_result = try get_output(test_file, .treewalk);
    defer std.testing.allocator.free(treewalk_result);

    // Ensure the bytecode and treewalk interpreter are the same
    try std.testing.expectEqualStrings(byte_result, treewalk_result);

    // If we have <filename>.expected, then check against that too
    const expected_name = name ++ ".expected";
    const expected_file = tests_dir.openFile(expected_name, .{ .mode = .read_only }) catch return;
    const expected = try expected_file.readToEndAlloc(std.testing.allocator, 1000);
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, byte_result);
}

fn get_output(test_file: []const u8, comptime interpreter: enum { byte, treewalk }) ![]u8 {
    const out = try outDir.dir.createFile(@tagName(interpreter) ++ ".out", .{ .read = true });

    const config = InterpretConfig {
        .filename = test_file,
        .interpreter_type = .byte
    };
    const cmd = Options {
        .interpret = config,
    };

    try Driver.init(std.testing.allocator, out.writer()).drive_with_opts(cmd);
    try out.seekTo(0);
    return try out.readToEndAlloc(std.testing.allocator, 1000);
}

test "output examples" {
    outDir = std.testing.tmpDir(.{});

    try run("minimal.min");
    try run("print.min");
    try run("binops.min");
    try run("simple_heap.min");
    try run("count_to_42.min");
    try run("recursive_fib.min");
    try run("unary_neg.min");

    outDir.cleanup();
}
