const std = @import("std");
const ArrayList = std.ArrayList;

const Driver = @import("driver/Driver.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const stdout = std.io.getStdOut().writer();

    Driver.init(gpa, stdout.any()).drive() catch {
        std.log.err("Fatal error occurred; aborting", .{});
    };
}

test {
    _ = @import("bytecode/interpret.zig");
    _ = @import("ir/passes/test.zig");
    _ = @import("ir/nodes/program.zig");
    _ = @import("ir/passes/blockify.zig");
    _ = @import("test/output.zig");
    _ = @import("test/ui.zig");
}
