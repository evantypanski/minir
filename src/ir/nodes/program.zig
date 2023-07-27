const std = @import("std");

const basic_block = @import("basic_block.zig");
const BasicBlock = basic_block.BasicBlock;
const BasicBlockBuilder = basic_block.BasicBlockBuilder;
const Decl = @import("decl.zig").Decl;
const FunctionBuilder = @import("decl.zig").FunctionBuilder;
const Stmt = @import("statement.zig").Stmt;
const Loc = @import("../sourceloc.zig").Loc;

pub const Program = struct {
    decls: []Decl,

    pub fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        for (self.decls) |*decl| {
            decl.deinit(allocator);
        }
        allocator.free(self.decls);
    }
};

pub const ProgramBuilder = struct {
    const Self = @This();

    decls: std.ArrayList(Decl),
    main_idx: ?usize,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .decls = std.ArrayList(Decl).init(allocator),
            .main_idx = null,
        };
    }

    pub fn addDecl(self: *Self, decl: Decl) !void {
        const is_main = switch (decl) {
            .function => |func| std.mem.eql(u8, func.name, "main"),
            .bb_function => |func| std.mem.eql(u8, func.name, "main"),
        };

        if (is_main) {
            if (self.main_idx != null) {
                return error.DuplicateMain;
            } else {
                self.main_idx = self.decls.items.len;
            }
        }

        try self.decls.append(decl);
    }

    pub fn build(self: *Self) !Program {
        if (self.main_idx == null) {
            return error.NoMainFunction;
        }
        return Program { .decls = try self.decls.toOwnedSlice() };
    }
};

test "deinit works" {
    const Value = @import("value.zig").Value;
    var func_builder = FunctionBuilder(BasicBlock).init(std.testing.allocator, "main");

    var bb1_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb1_builder.setLabel("bb1");
    try bb1_builder.addStatement(
        Stmt.init(
            .{
                .id = .{
                    .name = "hi",
                    .val = .{ .int = 99 },
                    .ty = .int,
                }
            },
            null,
            Loc.default()
        )
    );
    var hi_access = Value.initAccessName("hi");
    try bb1_builder.addStatement(
        Stmt.init(
            .{ .debug = hi_access },
            null,
            Loc.default()
        )
    );
    try bb1_builder.addStatement(
        Stmt.init(
            .{ .debug = Value.initCall("f", &.{}) },
            null,
            Loc.default()
        )
    );
    try func_builder.addElement(try bb1_builder.build());

    const func = try func_builder.build();

    var bb4_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb4_builder.setLabel("bb4");
    try bb4_builder.setTerminator(
        Stmt.init(
            .{.ret = Value.initInt(5)},
            null,
            Loc.default()
        )
    );

    var func2_builder = FunctionBuilder(BasicBlock).init(std.testing.allocator, "f");
    func2_builder.setReturnType(.int);
    try func2_builder.addElement(try bb4_builder.build());
    const func2 = try func2_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addDecl(Decl { .bb_function = func });
    try prog_builder.addDecl(Decl { .bb_function = func2 });

    var program = try prog_builder.build();
    program.deinit(std.testing.allocator);
}
