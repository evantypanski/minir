const std = @import("std");

const Allocator = std.mem.Allocator;

const Value = @import("value.zig").Value;

pub const TypeTag = enum {
    int,
    float,
    boolean,
    type_,
    pointer,
    // void but avoiding name conflicts is good :)
    none,
    // A runtime-known type, for example the return type of 'alloc'
    runtime,
    // this is only applied if we cannot determine the type
    err,
};

pub const Type = union(TypeTag) {
    int: void,
    float: void,
    boolean: void,
    type_: void,
    pointer: *const Type,
    none: void,
    runtime: void,
    err: void,

    // Initializes a pointer by allocating memory for the 'to' to live
    pub fn initPtrAlloc(to: Type, allocator: Allocator) !Type {
        const ty_ptr = try allocator.create(Type);
        ty_ptr.* = to;
        return .{
            .pointer = ty_ptr
        };
    }

    pub fn deinit(self: *Type, allocator: Allocator) void {
        switch (self.*) {
            .pointer => |*to| {
                @constCast(to.*).deinit(allocator);
                allocator.destroy(to.*);
            },
            else => {}
        }
    }

    /// Gets the size of this type in bytes
    pub fn size(self: Type) usize {
        return switch (self) {
            .err, .none => 0,
            // All types are allocated as a single value so... yeah
            else => @sizeOf(Value),
        };
    }

    /// A wrapper around type equality so that error types are equal to
    /// all other types. This helps avoid double diagnosing an error.
    pub fn eq(self: Type, other: Type) bool {
        // TODO: Real runtime type checking
        if (self == .err or other == .err or
            self == .runtime or other == .runtime) {
            return true;
        }

        // I don't know a better way to do this, you can only compare
        // a tagged union to an enum literal, not another tagged union.
        // I only want the tag too! :(
        switch (self) {
            .pointer => |self_to| {
                switch (other) {
                    .pointer => |other_to| return self_to.*.eq(other_to.*),
                    else => return false,
                }
            },
            .int => return other == .int,
            .float => return other == .float,
            .boolean => return other == .boolean,
            .type_ => return other == .type_,
            .none => return other == .none,
            .runtime, .err => return true,
        }
    }
};
