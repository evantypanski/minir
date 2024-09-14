//! Tests which ensure the output of bytecode and tree-walking interpreter
//! match the given expected value.

const std = @import("std");

const util = @import("util.zig");

// Runs the given test, where test is within the top-level 'tests/output' dir
fn run(comptime name: []const u8) !void {
    const tests_dir = try std.fs.cwd().openDir("tests/output", .{});
    const test_file = try tests_dir.realpathAlloc(std.testing.allocator, name);
    defer std.testing.allocator.free(test_file);

    // Bytecode interpreter
    const byte_result = try util.getOutput(test_file, .byte);
    defer std.testing.allocator.free(byte_result);

    // Bytecode interpreter, but through printing the bytecode
    const binary_result = try util.getOutput(test_file, .binary);
    defer std.testing.allocator.free(binary_result);

    // Treewalk interpreter
    const treewalk_result = try util.getOutput(test_file, .treewalk);
    defer std.testing.allocator.free(treewalk_result);

    // Ensure the bytecode and treewalk interpreter are the same
    try std.testing.expectEqualStrings(byte_result, treewalk_result);

    // If we have <filename>.expected, then check against that too
    const expected_name = name ++ ".expected";
    _ = try util.compareOutput(tests_dir, expected_name, byte_result);
}

test "output examples" {
    util.outDir = std.testing.tmpDir(.{});

    try run("minimal.min");
    try run("print.min");
    try run("binops.min");
    try run("simple_heap.min");
    try run("count_to_42.min");
    try run("recursive_fib.min");
    try run("unary_neg.min");
    try run("ptr_fn.min");
    try run("bool.min");

    util.outDir.cleanup();
}
