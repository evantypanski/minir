const std = @import("std");
const ascii = std.ascii;
const Allocator = std.mem.Allocator;

const Token = @import("token.zig").Token;
const SourceManager = @import("source_manager.zig").SourceManager;
const Loc = @import("sourceloc.zig").Loc;

const Trie = struct {
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

pub const Lexer = struct {
    pub const Error = error {
        Unexpected,
        InvalidIdentifier,
    };

    const Self = @This();

    source_mgr: SourceManager,
    current: usize,
    // Store the start in the lexer so we can grab an invalid token without
    // returning some fake error token
    start: usize,

    pub fn init(allocator: Allocator, source_mgr: SourceManager) !Self {
        const trie = try Trie.init(allocator);
        //try trie.add("hi", Token.Keyword.true_);
        // TODO
        trie.deinit();
        return .{
            .source_mgr = source_mgr,
            .current = 0,
            .start = 0,
        };
    }

    pub fn lex(self: *Self) Error!Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.isAtEnd()) {
            // EOF token has the last character as its slice
            return Token.init(
                .eof,
                self.source_mgr.len() - 1,
                self.source_mgr.len() - 1
            );
        }

        const c = self.advance();

        if (ascii.isAlphabetic(c) or c == '_') {
            return self.lexIdentifier();
        } else if (ascii.isDigit(c)) {
            return self.lexNumber();
        }

        return switch (c) {
            '!' => Token.init(.bang, self.start, self.current),
            '(' => Token.init(.lparen, self.start, self.current),
            ')' => Token.init(.rparen, self.start, self.current),
            '{' => Token.init(.lbrace, self.start, self.current),
            '}' => Token.init(.rbrace, self.start, self.current),
            '@' => Token.init(.at, self.start, self.current),
            ':' => Token.init(.colon, self.start, self.current),
            ';' => Token.init(.semi, self.start, self.current),
            ',' => Token.init(.comma, self.start, self.current),
            '=' => if (self.match('='))
                        Token.init(.eq_eq, self.start, self.current)
                    else
                        Token.init(.eq, self.start, self.current),
            '+' => Token.init(.plus, self.start, self.current),
            '-' => if (self.match('>'))
                        Token.init(.arrow, self.start, self.current)
                    else
                        Token.init(.minus, self.start, self.current),
            '*' => Token.init(.star, self.start, self.current),
            '/' => Token.init(.slash, self.start, self.current),
            '&' => if (self.match('&'))
                        Token.init(.amp_amp, self.start, self.current)
                    else
                        return error.Unexpected,
            '|' => if (self.match('|'))
                        Token.init(.pipe_pipe, self.start, self.current)
                    else
                        return error.Unexpected,
            '<' => if (self.match('='))
                        Token.init(.less_eq, self.start, self.current)
                    else
                        Token.init(.less, self.start, self.current),
            '>' => if (self.match('='))
                        Token.init(.greater_eq, self.start, self.current)
                    else
                        Token.init(.greater, self.start, self.current),

            else => error.Unexpected,
        };
    }

    pub fn lexNumber(self: *Self) Token {
        while (ascii.isDigit(self.peek())) : (_ = self.advance()) {}

        if (self.peek() == '.' and ascii.isDigit(self.peekNext())) {
            // Consume `.`
            _ = self.advance();
            while (ascii.isDigit(self.peek())) : (_ = self.advance()) {}
        }

        return Token.init(.num, self.start, self.current);
    }

    /// Gets the tag associated with the current token. Efficiently matches
    /// keywords :)
    ///
    /// Grabbed this tiny trie impl from crafting interpreters.
    /// TODO: The trie should be a separate struct and it's setup at the
    /// beginning
    fn identifierKw(self: Self) ?Token.Keyword {
        const token_len = self.current - self.start;
        switch (self.source_mgr.get(self.start)) {
            'a' => return self.checkKeyword(self.start + 1, 4, "lloc", .alloc),
            'f' => if (token_len >= 2) {
                    switch (self.source_mgr.get(self.start + 1)) {
                        'u' => return self.checkKeyword(self.start + 2, 2, "nc", .func),
                        'a' => return self.checkKeyword(self.start + 2, 3, "lse", .false_),
                        'l' => return self.checkKeyword(self.start + 2, 3, "oat", .float),
                        else => return null,
                    }
                } else {
                    return null;
                },
            'd' => return self.checkKeyword(self.start + 1, 4, "ebug", .debug),
            'i' => return self.checkKeyword(self.start + 1, 2, "nt", .int),
            'l' => return self.checkKeyword(self.start + 1, 2, "et", .let),
            'n' => return self.checkKeyword(self.start + 1, 3, "one", .none),
            't' => return self.checkKeyword(self.start + 1, 3, "rue", .true_),
            'u' => return self.checkKeyword(self.start + 1, 8, "ndefined", .undefined_),
            'r' => return self.checkKeyword(self.start + 1, 2, "et", .ret),
            'b' => if (token_len >= 2) {
                    switch (self.source_mgr.get(self.start + 1)) {
                        'r' => {
                            if (token_len == 2)
                                return .br
                            else
                                if (token_len == 3 and
                                    self.source_mgr.get(self.start + 2) == 'c')
                                    return .brc
                                else
                                    return null;
                        },
                        'o' => return self.checkKeyword(self.start + 2, 5, "olean", .boolean),
                        else => return null,
                    }
                } else {
                    return null;
                },
            else => return null,
        }
    }

    fn checkKeyword(self: Self, start: usize, len: usize,
        rest: []const u8, kw: Token.Keyword) ?Token.Keyword {
        if (self.current - start == len
            and std.mem.eql(
                u8,
                self.source_mgr.snip(start, self.current),
                rest)
            ) {
                return kw;
        }

        return null;
    }

    pub fn lexIdentifier(self: *Self) Token {

        while (ascii.isAlphabetic(self.peek())
            or ascii.isDigit(self.peek())
            or self.peek() == '_')
                : (_ = self.advance()) {}
        const opt_kw = self.identifierKw();
        return if (opt_kw) |kw|
            Token.initKw(kw, self.start, self.current)
        else
            Token.init(.identifier, self.start, self.current);
    }

    pub fn getTokString(self: Self, token: Token) []const u8 {
        return self.source_mgr.snip(token.loc.start, token.loc.end);
    }

    /// Gets the Loc for the last token lexed or failed to lex
    pub fn getLastLoc(self: Self) Loc {
        return Loc.init(self.start, self.current);
    }

    fn advance(self: *Self) u8 {
        self.current += 1;
        return self.source_mgr.get(self.current - 1);
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) {
            return false;
        }
        if (self.source_mgr.get(self.current) != expected) {
            return false;
        }

        self.current += 1;
        return true;
    }

    fn peek(self: Self) u8 {
        return self.source_mgr.get(self.current);
    }

    fn peekNext(self: Self) u8 {
        if (self.isAtEnd()) {
            return 0;
        }
        return self.source_mgr.get(self.current + 1);
    }

    fn skipWhitespace(self: *Self) void {
        while (self.current < self.source_mgr.len()
            and ascii.isWhitespace(self.peek()))
            : (self.current += 1) {}
    }

    pub inline fn isAtEnd(self: Self) bool {
        return self.current >= self.source_mgr.len();
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
