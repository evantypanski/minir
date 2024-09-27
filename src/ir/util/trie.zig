const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Trie(comptime Tag: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        root: *TrieNode(Tag),

        pub fn init(allocator: Allocator) !Self {
            const root = try allocator.create(TrieNode(Tag));
            root.* = TrieNode(Tag).init(null);
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
            const root = try allocator.create(TrieNode(Tag));
            root.* = TrieNode(Tag).init(null);
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
            var current: ?*TrieNode(Tag) = self.root;
            for (str) |char| {
                var child = try current.?.getChild(char);
                if (child == null) {
                    child = try self.allocator.create(TrieNode(Tag));
                    child.?.* = TrieNode(Tag).init(null);
                    // Set the child: Do this better, maybe in the node all at once
                    current.?.children[try TrieNode(Tag).positionFor(char)] = child;
                }
                current = child;
            }

            current.?.*.tag = tag;
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

            return current.tag;
        }
    };
}

fn TrieNode(comptime Tag: type) type {
    return struct {
        const Self = @This();

        // 0-9 are digits 0-9, 10-35 are alphabet, 36 is '_'
        // No upper-case ids in keywords yet
        children: [37]?*TrieNode(Tag),
        tag: ?Tag,

        pub fn init(tag: ?Tag) Self {
            return Self {
                .children = [_]?*TrieNode(Tag) {null}**37,
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

        pub fn getChild(self: Self, ch: u8) !?*TrieNode(Tag) {
            const pos = try positionFor(ch);
            return self.children[pos];
        }

        pub fn positionFor(ch: u8) !usize {
            if (ch == '_') return 36;

            if (ch >= '0' and ch <= '9') {
                return ch - 48;
            }

            if (ch >= 'a' and ch <= 'z') {
                return ch - 97 + 10;
            }

            return error.InvalidIdentifier;
        }
    };
}

test "Trie can add and retrieve tags" {
    const MyEnum = enum {
        one,
        two,
        three,
        f_o_u_r,
        five_,
    };

    const trie = try Trie(MyEnum).init(std.testing.allocator);
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
    const trie = try Trie(MyEnum).initFromTags(std.testing.allocator);
    defer trie.deinit();

    try std.testing.expectEqual(trie.get("one"), MyEnum.one);
    try std.testing.expectEqual(trie.get("five"), MyEnum.five_);
    try std.testing.expect(trie.get("five_") != MyEnum.five_);
}
