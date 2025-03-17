const std = @import("std");

const util = @import("util.zig");

// Runs the given test, where test is within the top-level 'tests/ui' dir
fn run(comptime name: []const u8) !void {
    // TODO: Get executable better?
    const minir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "zig-out/bin/minir");
    defer std.testing.allocator.free(minir);

    const ui_dir_name = "tests/ui/";

    const argv = [_][]const u8{ minir, "interpret", ui_dir_name ++ name };
    var proc = std.process.Child.init(&argv, std.testing.allocator);
    proc.stdin_behavior = .Ignore;
    proc.stdout_behavior = .Pipe;
    proc.stderr_behavior = .Pipe;

    try proc.spawn();

    var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
    var stderr_list: std.ArrayListUnmanaged(u8) = .empty;

    try proc.collectOutput(std.testing.allocator, &stdout_list, &stderr_list, 10000);

    const stdout = try stdout_list.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(stdout);

    const stderr = try stderr_list.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(stderr);

    const tests_dir = try std.fs.cwd().openDir(ui_dir_name, .{});
    // Now we have stdout and stderr - test to make sure they're what we expect
    // If they don't exist, bless them
    const stdout_expected_name = name ++ ".stdout";
    if (!try util.compareOutput(tests_dir, stdout_expected_name, stdout)) {
        try util.bless(tests_dir, stdout_expected_name, stdout);
    }

    const stderr_expected_name = name ++ ".stderr";
    if (!try util.compareOutput(tests_dir, stderr_expected_name, stderr)) {
        try util.bless(tests_dir, stderr_expected_name, stderr);
    }
}

test "error examples" {
    try run("notminir.min");
    try run("kwuse.min");
    try run("invalidtypes.min");
    try run("unreachable.min");
}
