const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("../token.zig").Token;

// TODO: Make the trie generic so it doesn't assume Token.Keyword is its tag
pub const Trie = struct {
    const Self = @This();

    allocator: Allocator,
    root: *TrieNode,

    pub fn init(allocator: Allocator) !Self {
        const root = try allocator.create(TrieNode);
        root.* = TrieNode.init(null);
        return Self {
            .allocator = allocator,
            .root = root,
        };
    }

    /// Initializes the trie from an enum type. Keywords are created with
    /// the various keys. If there is a trailing underscore, that is not
    /// counted.
    pub fn initFromTags(allocator: Allocator, enum_ty: type) !Self {
        const tags = std.enums.values(enum_ty);
        const root = try allocator.create(TrieNode);
        root.* = TrieNode.init(null);
        var result = Self {
            .allocator = allocator,
            .root = root,
        };

        for (tags) |tag| {
            var name = std.enums.tagName(enum_ty, tag) orelse continue;

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

    pub fn add(self: Self, str: []const u8, tag: Token.Keyword) !void {
        var current: ?*TrieNode = self.root;
        for (str) |char| {
            var child = try current.?.getChild(char);
            if (child == null) {
                child = try self.allocator.create(TrieNode);
                child.?.* = TrieNode.init(null);
                // Set the child: Do this better, maybe in the node all at once
                current.?.children[try TrieNode.positionFor(char)] = child;
            }
            current = child;
        }

        current.?.*.tag = tag;
    }

    pub fn get(self: Self, str: []const u8) ?Token.Keyword {
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

const TrieNode = struct {
    const Self = @This();

    // 0-9 are digits 0-9, 10-35 are alphabet, 36 is '_'
    // No upper-case ids in keywords yet
    children: [37]?*TrieNode,
    tag: ?Token.Keyword,

    pub fn init(tag: ?Token.Keyword) Self {
        return Self {
            .children = [_]?*TrieNode {null}**37,
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

    pub fn getChild(self: Self, ch: u8) !?*TrieNode {
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

test "Trie can add and retrieve tags" {
    const trie = try Trie.init(std.testing.allocator);
    defer trie.deinit();

    try trie.add("true", Token.Keyword.true_);
    try trie.add("false", Token.Keyword.false_);
    try trie.add("none", Token.Keyword.none);
    // Underscore should work
    try trie.add("my_custom_id", Token.Keyword.func);

    try std.testing.expectEqual(trie.get("true"), Token.Keyword.true_);
    try std.testing.expectEqual(trie.get("false"), Token.Keyword.false_);
    try std.testing.expectEqual(trie.get("none"), Token.Keyword.none);
    try std.testing.expectEqual(trie.get("my_custom_id"), Token.Keyword.func);
    try std.testing.expectEqual(trie.get("not_a_keyword"), null);
}

test "Trie from an enum" {
    const trie = try Trie.initFromTags(std.testing.allocator, Token.Keyword);
    defer trie.deinit();

    try std.testing.expectEqual(trie.get("true"), Token.Keyword.true_);
    try std.testing.expect(trie.get("true_") != Token.Keyword.true_);
    try std.testing.expectEqual(trie.get("none"), Token.Keyword.none);
}
