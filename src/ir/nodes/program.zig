const std = @import("std");

const BasicBlockBuilder = @import("basic_block.zig").BasicBlockBuilder;
const Function = @import("function.zig").Function;
const FunctionBuilder = @import("function.zig").FunctionBuilder;
const Instr = @import("instruction.zig").Instr;

pub const Program = struct {
    functions: []Function,

    pub fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        for (self.functions) |*function| {
            function.deinit(allocator);
        }
        allocator.free(self.functions);
    }
};

pub const ProgramBuilder = struct {
    const Self = @This();

    functions: std.ArrayList(Function),
    main_idx: ?usize,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .functions = std.ArrayList(Function).init(allocator),
            .main_idx = null,
        };
    }

    pub fn addFunction(self: *Self, func: Function) !void {
        const is_main = std.mem.eql(u8, func.name, "main");
        if (is_main) {
            if (self.main_idx != null) {
                return error.DuplicateMain;
            } else {
                self.main_idx = self.functions.items.len;
            }
        }

        try self.functions.append(func);
    }

    pub fn build(self: *Self) !Program {
        if (self.main_idx == null) {
            return error.NoMainFunction;
        }
        return Program { .functions = try self.functions.toOwnedSlice() };
    }
};

test "deinit works" {
    const Value = @import("value.zig").Value;
    var func_builder = FunctionBuilder.init(std.testing.allocator, "main");
    defer func_builder.deinit();

    var bb1_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb1_builder.setLabel("bb1");
    try bb1_builder.addInstruction(
        Instr {
            .id = .{
                .name = "hi",
                .val = .{ .int = 99 },
                .ty = .int,
            }
        }
    );
    var hi_access = Value.initAccessName("hi");
    try bb1_builder.addInstruction(Instr{ .debug = hi_access });
    try bb1_builder.addInstruction(.{ .debug = Value.initCall("f", &.{}) });
    try func_builder.addBasicBlock(try bb1_builder.build());

    const func = try func_builder.build();

    var bb4_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb4_builder.setLabel("bb4");
    try bb4_builder.setTerminator(.{.ret = Value.initInt(5)});

    var func2_builder = FunctionBuilder.init(std.testing.allocator, "f");
    defer func2_builder.deinit();
    func2_builder.setReturnType(.int);
    try func2_builder.addBasicBlock(try bb4_builder.build());
    const func2 = try func2_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addFunction(func);
    try prog_builder.addFunction(func2);

    var program = try prog_builder.build();
    program.deinit(std.testing.allocator);
}
