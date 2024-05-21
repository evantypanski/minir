//! Common testing utilities
const std = @import("std");

const Dir = std.fs.Dir;
const Driver = @import("../driver/Driver.zig");
const InterpretConfig = @import("../driver/options.zig").InterpretConfig;
const Options = @import("../driver/options.zig").Options;

pub var outDir: std.testing.TmpDir = undefined;

/// Compares the actual output to the expected file in the directory.
/// Returns false if the file does not exist, true if it does. This is
/// regardless of the test expectation result.
pub fn compareOutput(dir: Dir, expected_name: []const u8, actual: []u8) !bool {
    const expected = getFileContent(dir, expected_name) catch return false;
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, actual);

    return true;
}

/// Gets the content of the file using the testing allocator. Be sure to
/// free it
pub fn getFileContent(dir: Dir, name: []const u8) ![]u8 {
    const file = try dir.openFile(name, .{ .mode = .read_only });
    const content = try file.readToEndAlloc(std.testing.allocator, 10000);
    file.close();
    return content;
}

/// Writes the actual content to the given file
pub fn bless(dir: Dir, name: []const u8, content: []u8) !void {
    const file = try dir.createFile(name, .{});
    try file.writer().writeAll(content);
    file.close();
}

/// Gets the output from running minir with a given interpreter
///
/// MUST set outDir in this before using this function.
pub fn getOutput(
    test_file: []const u8,
    comptime interpreter: enum { byte, treewalk }
) ![]u8 {
    // outDir must be set if trying to get the output, otherwise the following
    // file creation will fail. It's done this way to better reuse the output
    // dir easily. We could also just pass it in a few functions, but this is a
    // test anyway, so.
    const out = try outDir.dir.createFile(
        @tagName(interpreter) ++ ".out", .{ .read = true }
    );

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

