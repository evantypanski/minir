const std = @import("std");
const ascii = std.ascii;

const Token = @import("token.zig").Token;
const LexError = @import("errors.zig").LexError;
const SourceManager = @import("source_manager.zig").SourceManager;
const Loc = @import("sourceloc.zig").Loc;

pub const Lexer = struct {
    const Self = @This();

    source_mgr: SourceManager,
    current: usize,
    // Store the start in the lexer so we can grab an invalid token without
    // returning some fake error token
    start: usize,

    pub fn init(source_mgr: SourceManager) Self {
        return .{
            .source_mgr = source_mgr,
            .current = 0,
            .start = 0,
        };
    }

    pub fn lex(self: *Self) LexError!Token {
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

        var c = self.advance();

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
    fn identifierTag(self: Self) Token.Tag {
        const token_len = self.current - self.start;
        switch (self.source_mgr.get(self.start)) {
            'a' => return self.checkKeyword(self.start + 1, 4, "lloc", .alloc),
            'f' => if (token_len >= 2) {
                    switch (self.source_mgr.get(self.start + 1)) {
                        'u' => return self.checkKeyword(self.start + 2, 2, "nc", .func),
                        'a' => return self.checkKeyword(self.start + 2, 3, "lse", .false_),
                        'l' => return self.checkKeyword(self.start + 2, 2, "oat", .float),
                        else => return .identifier,
                    }
                } else {
                    return .identifier;
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
                                    return .identifier;
                        },
                        'o' => return self.checkKeyword(self.start + 1, 5, "olean", .boolean),
                        else => return .identifier,
                    }
                } else {
                    return .identifier;
                },
            else => return .identifier,
        }
    }

    fn checkKeyword(self: Self, start: usize, len: usize,
        rest: []const u8, tag: Token.Tag) Token.Tag {
        if (self.current - start == len
            and std.mem.eql(
                u8,
                self.source_mgr.snip(start, self.current),
                rest)
            ) {
                return tag;
        }

        return .identifier;
    }

    pub fn lexIdentifier(self: *Self) Token {

        while (ascii.isAlphabetic(self.peek())
            or ascii.isDigit(self.peek())
            or self.peek() == '_')
                : (_ = self.advance()) {}
        return Token.init(self.identifierTag(), self.start, self.current);
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
