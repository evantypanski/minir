const std = @import("std");
const ArrayList = std.ArrayList;

const Driver = @import("driver/Driver.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const stdout = std.io.getStdOut().writer();

    try Driver.init(gpa, stdout).drive();
}

test {
    _ = @import("bytecode/interpret.zig");
    _ = @import("ir/nodes/program.zig");
    _ = @import("ir/passes/blockify.zig");
}
