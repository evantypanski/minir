const std = @import("std");

const statement = @import("statement.zig");
const VarDecl = statement.VarDecl;
const BasicBlock = @import("basic_block.zig").BasicBlock;
const Type = @import("type.zig").Type;

pub fn Function(comptime ElementType: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        elements: []ElementType,
        params: []VarDecl,
        ret_ty: Type,

        pub fn init(name: []const u8, elements: []ElementType,
                    params: []VarDecl, ret_ty: Type) !Self {
            return .{
                .name = name,
                .elements = elements,
                .params = params,
                .ret_ty = ret_ty,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.elements) |*element| {
                element.deinit(allocator);
            }
            allocator.free(self.elements);
            allocator.free(self.params);
        }

        // Dunno how else to do this. This will just free what this function
        // directly allocated, not owning its elements.
        pub fn shallowDeinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.elements);
            allocator.free(self.params);
        }
    };
}

pub fn FunctionBuilder(comptime ElementType: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        elements: std.ArrayList(ElementType),
        params: std.ArrayList(VarDecl),
        label_map: std.StringHashMap(usize),
        ret_ty: ?Type,

        pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
            return .{
                .name = name,
                .elements = std.ArrayList(ElementType).init(allocator),
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

        pub fn addElement(self: *Self, element: ElementType) !void {
            try self.elements.append(element);
        }

        pub fn setReturnType(self: *Self, ty: Type) void {
            self.ret_ty = ty;
        }

        pub fn addParam(self: *Self, param_decl: VarDecl) !void {
            try self.params.append(param_decl);
        }

        pub fn build(self: *Self) !Function(ElementType) {
            return Function(ElementType).init(self.name, try self.elements.toOwnedSlice(),
                                 try self.params.toOwnedSlice(),
                                 self.ret_ty orelse .none);
        }
    };
}

pub const DeclKind = enum {
    function,
    bb_function,
};

pub const Decl = union(DeclKind) {
    function: Function(statement.Stmt),
    bb_function: Function(BasicBlock),

    pub fn deinit(self: *Decl, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .function => |*func| func.deinit(allocator),
            .bb_function => |*func| func.deinit(allocator),
        }
    }
};
