const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Trie(comptime Tag: type, comptime Node: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        root: *Node,

        pub fn init(allocator: Allocator) !Self {
            const root = try allocator.create(Node);
            root.* = Node.init(null);
            return Self {
                .allocator = allocator,
                .root = root,
            };
        }

        /// Initializes the trie from an enum type. Keywords are created with
        /// the various keys. If there is a trailing underscore, that is not
        /// counted.
        pub fn initFromTags(allocator: Allocator) !Self {
            const tags = std.enums.values(Tag);
            const root = try allocator.create(Node);
            root.* = Node.init(null);
            var result = Self {
                .allocator = allocator,
                .root = root,
            };

            for (tags) |tag| {
                var name = std.enums.tagName(Tag, tag) orelse continue;

                // Remove the trailing '_' if it exists
                name = if (name[name.len - 1] == '_')
                    name[0..name.len-1]
                else
                    name[0..name.len];

                // Add to the trie
                try result.add(name, tag);
            }

            return result;
        }

        pub fn deinit(self: Self) void {
            self.root.deinit(self.allocator);
        }

        pub fn add(self: Self, str: []const u8, tag: Tag) !void {
            var current: ?*Node = self.root;
            for (str) |char| {
                var child = try current.?.getChild(char);
                if (child == null) {
                    child = try self.allocator.create(Node);
                    child.?.* = Node.init(null);
                    // Set the child: Do this better, maybe in the node all at once
                    try current.?.setChild(child, char);
                }
                current = child;
            }

            current.?.*.setTag(tag);
        }

        pub fn get(self: Self, str: []const u8) ?Tag {
            var current = self.root;
            for (str) |char| {
                const child = current.getChild(char) catch return null;
                if (child == null) {
                    return null;
                }

                current = child.?;
            }

            return current.getTag();
        }
    };
}

pub const TrieError = error {
    InvalidIdentifier
};

fn TrieNode(comptime Tag: type, comptime BaseTy: type) type {
    return struct {
        pub const Self = @This();

        inner: BaseTy,

        pub fn init(tag: ?Tag) Self {
            return .{
                .inner = BaseTy.init(tag),
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            return self.inner.deinit(allocator);
        }

        pub fn getChild(self: Self, ch: u8) TrieError!?*Self {
            return self.inner.getChild(ch);
        }

        pub fn setChild(self: *Self, child: ?*Self, ch: u8) TrieError!void {
            self.inner.children[try positionFor(ch)] = child;
        }

        pub fn setTag(self: *Self, tag: Tag) void {
            self.inner.tag = tag;
        }

        pub fn getTag(self: *Self) ?Tag {
            return self.inner.tag;
        }

        pub fn positionFor(ch: u8) TrieError!usize {
            return BaseTy.positionFor(ch);
        }
    };
}

pub fn AsciiTrieNode(comptime Tag: type) type {
    return TrieNode(
        Tag,
        struct {
            pub const Self = @This();
            pub const Outer = TrieNode(Tag, Self);

            // 0-9 are digits 0-9, 10-35 are alphabet, 36 is '_'
            // No upper-case ids in keywords yet
            children: [37]?*Outer,
            tag: ?Tag,

            pub fn init(tag: ?Tag) Self {
                return Self {
                    .children = [_]?*Outer {null}**37,
                    .tag = tag,
                };
            }

            pub fn deinit(self: *Self, allocator: Allocator) void {
                inline for (self.children) |opt_child| {
                    if (opt_child) |child| {
                        child.deinit(allocator);
                    }
                }
                allocator.destroy(self);
            }

            pub fn getChild(self: Self, ch: u8) TrieError!?*Outer {
                const pos = try positionFor(ch);
                return self.children[pos];
            }

            pub fn positionFor(ch: u8) TrieError!usize {
                if (ch == '_') return 36;

                if (ch >= '0' and ch <= '9') {
                    return ch - 48;
                }

                if (ch >= 'a' and ch <= 'z') {
                    return ch - 97 + 10;
                }

                return error.InvalidIdentifier;
            }
        }
    );
}

test "Trie can add and retrieve tags" {
    const MyEnum = enum {
        one,
        two,
        three,
        f_o_u_r,
        five_,
    };

    const trie = try Trie(MyEnum, AsciiTrieNode(MyEnum)).init(std.testing.allocator);
    defer trie.deinit();

    try trie.add("one", MyEnum.one);
    try trie.add("two", MyEnum.two);
    try trie.add("three", MyEnum.three);
    // Underscore should work
    try trie.add("f_o_u_r", MyEnum.f_o_u_r);
    // Underscore at the end should work if added directly
    try trie.add("five_", MyEnum.five_);

    try std.testing.expectEqual(trie.get("one"), MyEnum.one);
    try std.testing.expectEqual(trie.get("two"), MyEnum.two);
    try std.testing.expectEqual(trie.get("three"), MyEnum.three);
    try std.testing.expectEqual(trie.get("f_o_u_r"), MyEnum.f_o_u_r);
    try std.testing.expectEqual(trie.get("five_"), MyEnum.five_);
    try std.testing.expectEqual(trie.get("not_a_keyword"), null);
}

test "Trie from an enum" {
    const MyEnum = enum {
        one,
        two,
        three,
        f_o_u_r,
        five_,
    };
    const trie = try Trie(MyEnum, AsciiTrieNode(MyEnum)).initFromTags(std.testing.allocator);
    defer trie.deinit();

    try std.testing.expectEqual(trie.get("one"), MyEnum.one);
    try std.testing.expectEqual(trie.get("five"), MyEnum.five_);
    try std.testing.expect(trie.get("five_") != MyEnum.five_);
}
