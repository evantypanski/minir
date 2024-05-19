const std = @import("std");

// Runs the given test, where test is within the top-level 'tests/ui' dir
fn run(comptime name: []const u8) !void {
    // TODO: Get executable better?
    const minir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "zig-out/bin/minir");
    defer std.testing.allocator.free(minir);

    const ui_dir_name = "tests/ui/";

    const argv = [_][]const u8{ minir, "interpret", ui_dir_name ++ name };
    var proc = std.ChildProcess.init(&argv, std.testing.allocator);
    proc.stdin_behavior = .Ignore;
    proc.stdout_behavior = .Pipe;
    proc.stderr_behavior = .Pipe;

    try proc.spawn();

    var stdout_list = std.ArrayList(u8).init(std.testing.allocator);

    var stderr_list = std.ArrayList(u8).init(std.testing.allocator);

    try proc.collectOutput(&stdout_list, &stderr_list, 10000);

    const stdout = try stdout_list.toOwnedSlice();
    defer std.testing.allocator.free(stdout);

    const stderr = try stderr_list.toOwnedSlice();
    defer std.testing.allocator.free(stderr);

    // Now we have stdout and stderr - test to make sure they're what we expect
    const stdout_expected_name = name ++ ".stdout";
    const stderr_expected_name = name ++ ".stderr";

    const tests_dir = try std.fs.cwd().openDir(ui_dir_name, .{});

    const stdout_expected_file = try tests_dir.openFile(
        stdout_expected_name, .{ .mode = .read_only }
    );
    const stderr_expected_file = try tests_dir.openFile(
        stderr_expected_name, .{ .mode = .read_only }
    );

    const stdout_expected =
        try stdout_expected_file.readToEndAlloc(std.testing.allocator, 10000);
    defer std.testing.allocator.free(stdout_expected);

    const stderr_expected =
        try stderr_expected_file.readToEndAlloc(std.testing.allocator, 10000);
    defer std.testing.allocator.free(stderr_expected);

    try std.testing.expectEqualStrings(stdout_expected, stdout);
    try std.testing.expectEqualStrings(stderr_expected, stderr);
}


test "error examples" {
    try run("notminir.min");
}
