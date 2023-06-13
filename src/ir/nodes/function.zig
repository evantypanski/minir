const std = @import("std");

const instruction = @import("instruction.zig");
const VarDecl = instruction.VarDecl;
const BasicBlock = @import("basic_block.zig").BasicBlock;
const Type = @import("type.zig").Type;

pub const Function = struct {
    const Self = @This();

    name: []const u8,
    // TODO: Basic blocks should just be an instruction then you can just
    // "blockify" a function?
    bbs: []BasicBlock,
    params: []VarDecl,
    ret_ty: Type,

    pub fn init(name: []const u8, bbs: []BasicBlock,
                params: []VarDecl, ret_ty: Type) !Self {
        return .{
            .name = name,
            .bbs = bbs,
            .params = params,
            .ret_ty = ret_ty,
        };
    }

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.bbs) |*bb| {
            bb.deinit(allocator);
        }
        allocator.free(self.bbs);
        allocator.free(self.params);
    }
};

pub const FunctionBuilder = struct {
    const Self = @This();

    name: []const u8,
    bbs: std.ArrayList(BasicBlock),
    params: std.ArrayList(VarDecl),
    label_map: std.StringHashMap(usize),
    ret_ty: ?Type,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .name = name,
            .bbs = std.ArrayList(BasicBlock).init(allocator),
            .params = std.ArrayList(VarDecl).init(allocator),
            .label_map = std.StringHashMap(usize).init(allocator),
            .ret_ty = null,
        };
    }

    // Only frees memory owned by this builder, not what would be owned by
    // what it creates.
    pub fn deinit(self: *Self) void {
        self.label_map.deinit();
    }

    pub fn addBasicBlock(self: *Self, bb: BasicBlock) !void {
        if (bb.label) |label| {
            try self.label_map.put(label, self.bbs.items.len);
        }
        try self.bbs.append(bb);
    }

    pub fn setReturnType(self: *Self, ty: Type) void {
        self.ret_ty = ty;
    }

    pub fn addParam(self: *Self, param_decl: VarDecl) !void {
        try self.params.append(param_decl);
    }

    pub fn build(self: *Self) !Function {
        // Use map to set indexes in basic blocks
        var i: usize = 0;
        while (i < self.bbs.items.len) : (i += 1) {
            var bb = self.bbs.items[i];
            if (bb.terminator) |*terminator| {
                switch (terminator.*) {
                    .branch => |*branch| {
                        const index = self.label_map.get(branch.labelName())
                                orelse return error.UnknownLabel;
                        branch.setIndex(index);
                    },
                    else => {},
                }
            }
        }

        return Function.init(self.name, try self.bbs.toOwnedSlice(),
                             try self.params.toOwnedSlice(),
                             self.ret_ty orelse .none);
    }
};

