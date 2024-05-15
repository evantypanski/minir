const std = @import("std");

const statement = @import("statement.zig");
const VarDecl = statement.VarDecl;
const BasicBlock = @import("basic_block.zig").BasicBlock;
const Type = @import("type.zig").Type;
const StaticStringMap = std.static_string_map.StaticStringMap;

pub const BuiltinKind = enum {
    alloc,
    debug,
};

pub const builtins = blk: {
    break :blk StaticStringMap(*const Decl).initComptime(.{
        .{
            "alloc", &.{ .builtin = .{
                .params = &.{ VarDecl{ .name = "ty", .val = null, .ty = Type.type_ }},
                .ret_ty = Type { .pointer = &.{.runtime = {} } },
                .kind = .alloc
            }}
        },
        .{
            "debug", &.{ .builtin = .{
                .params = &.{ VarDecl{ .name = "val", .val = null, .ty = Type.runtime }},
                .ret_ty = .none,
                .kind = .debug
            }}
        }
    });
};

pub const Builtin = struct {
    const Self = @This();

    params: []const VarDecl,
    ret_ty: Type,
    kind: BuiltinKind,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.params) |*param| {
            @constCast(param).deinit(allocator);
        }
        allocator.free(self.params);
        self.ret_ty.deinit(allocator);
    }
};

pub fn Function(comptime ElementType: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        elements: []ElementType,
        params: []VarDecl,
        ret_ty: Type,

        pub fn init(name: []const u8, elements: []ElementType,
                    params: []VarDecl, ret_ty: Type) Self {
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
            for (self.params) |*param| {
                param.deinit(allocator);
            }
            allocator.free(self.params);
            self.ret_ty.deinit(allocator);
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
        ret_ty: ?Type,

        pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
            return .{
                .name = name,
                .elements = std.ArrayList(ElementType).init(allocator),
                .params = std.ArrayList(VarDecl).init(allocator),
                .ret_ty = null,
            };
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
            return Function(ElementType)
                .init(self.name, try self.elements.toOwnedSlice(),
                      try self.params.toOwnedSlice(), self.ret_ty orelse .none);
        }
    };
}

pub const DeclKind = enum {
    function,
    bb_function,
    builtin,
};

pub const Decl = union(DeclKind) {
    function: Function(statement.Stmt),
    bb_function: Function(BasicBlock),
    builtin: Builtin,

    pub fn name(self: Decl) []const u8 {
        return switch (self) {
            .function => |function| function.name,
            .bb_function => |bb_function| bb_function.name,
            .builtin => |builtin| @tagName(builtin.kind),
        };
    }

    pub fn ty(self: Decl) Type {
        return switch (self) {
            .function => |function| function.ret_ty,
            .bb_function => |bb_function| bb_function.ret_ty,
            .builtin => |builtin| builtin.ret_ty,
        };
    }

    pub fn params(self: Decl) []const VarDecl {
        return switch (self) {
            .function => |function| function.params,
            .bb_function => |bb_function| bb_function.params,
            .builtin => |builtin| builtin.params,
        };
    }

    pub fn deinit(self: *Decl, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .function => |*func| func.deinit(allocator),
            .bb_function => |*func| func.deinit(allocator),
            .builtin => |*builtin| builtin.deinit(allocator),
        }
    }
};
