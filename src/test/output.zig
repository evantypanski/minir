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
    const interpret = CommandLine.InterpretConfig {
        .filename = test_file,
        .interpreter_type = .byte
    };
    const config = CommandLine.CommandLineResult { .interpret = interpret };
    // TODO: Get output, then compare
    const stdout = std.io.getStdOut().writer();

    try Driver.init(std.testing.allocator, stdout).drive_with_opts(config);
}

test "output examples" {
    try run("minimal.min");
}
