const std = @import("std");
const ascii = std.ascii;

const Token = @import("token.zig").Token;

pub const LexError = error {
    Unexpected,
};

pub const Lexer = struct {
    const Self = @This();

    source: []u8,
    current: usize,

    pub fn init(source: []u8) Self {
        return .{
            .source = source,
            .current = 0,
        };
    }

    pub fn lex(self: *Self) LexError!Token {
        self.skipWhitespace();
        const start = self.current;

        if (self.isAtEnd()) {
            // EOF token has the last character as its slice
            return Token.init(.EOF, self.source.len - 1, self.source.len - 1);
        }

        var c = self.advance();

        if (ascii.isAlphabetic(c) or c == '_') {
            return self.lexIdentifier(start);
        } else if (ascii.isDigit(c)) {
            return self.lexNumber(start);
        }

        return switch (c) {
            '(' => Token.init(.LPAREN, start, self.current),
            ')' => Token.init(.RPAREN, start, self.current),
            '{' => Token.init(.LBRACE, start, self.current),
            '}' => Token.init(.RBRACE, start, self.current),
            '@' => Token.init(.AT, start, self.current),
            ':' => Token.init(.COLON, start, self.current),
            ',' => Token.init(.COMMA, start, self.current),
            '=' => if (self.match('='))
                        Token.init(.EQ_EQ, start, self.current)
                    else
                        Token.init(.EQ, start, self.current),
            '+' => Token.init(.PLUS, start, self.current),
            '-' => if (self.match('>'))
                        Token.init(.ARROW, start, self.current)
                    else
                        Token.init(.MINUS, start, self.current),
            '*' => Token.init(.STAR, start, self.current),
            '/' => Token.init(.SLASH, start, self.current),
            '&' => if (self.match('&'))
                        Token.init(.AMP_AMP, start, self.current)
                    else
                        return error.Unexpected,
            '|' => if (self.match('|'))
                        Token.init(.PIPE_PIPE, start, self.current)
                    else
                        return error.Unexpected,
            '<' => if (self.match('='))
                        Token.init(.GREATER_EQ, start, self.current)
                    else
                        Token.init(.GREATER, start, self.current),
            '>' => if (self.match('='))
                        Token.init(.LESS_EQ, start, self.current)
                    else
                        Token.init(.LESS, start, self.current),

            else => error.Unexpected,
        };
    }

    pub fn lexNumber(self: *Self, start: usize) Token {
        while (ascii.isDigit(self.peek())) : (_ = self.advance()) {}

        if (self.peek() == '.' and ascii.isDigit(self.peekNext())) {
            // Consume `.`
            _ = self.advance();
            while (ascii.isDigit(self.peek())) : (_ = self.advance()) {}
        }

        return Token.init(.NUM, start, self.current);
    }

    /// Gets the tag associated with the current token. Efficiently matches
    /// keywords :)
    ///
    /// It's pretty overkill with so few. But oh well. Grabbed this tiny trie
    /// impl from crafting interpreters.
    fn identifierTag(self: Self, start: usize) Token.Tag {
        const token_len = self.current - start;
        switch (self.source[start]) {
            'f' => return self.checkKeyword(start + 1, 1, "n", .FN),
            'd' => return self.checkKeyword(start + 1, 4, "ebug", .DEBUG),
            // Just do branches here because why not. This is a mess. Oops.
            'b' => if (token_len >= 2) {
                    switch (self.source[start + 1]) {
                        'r' => {
                            if (token_len == 2)
                                return .BR
                            else
                                return switch (self.source[start + 2]) {
                                    'z' => .BRZ,
                                    'e' => .BRE,
                                    'l' => if (token_len > 3)
                                                self.checkKeyword(start + 2, 2,
                                                        "le", .BRLE)
                                            else
                                                .BRL,
                                    'g' => if (token_len > 3)
                                                self.checkKeyword(start + 2, 2,
                                                        "ge", .BRGE)
                                            else
                                                .BRG,
                                    else => .IDENTIFIER,
                                };
                        },
                        else => return .IDENTIFIER,
                    }
                } else {
                    return .IDENTIFIER;
                },
            else => return .IDENTIFIER,
        }
    }

    fn checkKeyword(self: Self, start: usize, len: usize,
        rest: []const u8, tag: Token.Tag) Token.Tag {
        if (self.current - start == len
            and std.mem.eql(u8, self.source[start..self.current], rest)) {
            return tag;
        }

        return .IDENTIFIER;
    }

    pub fn lexIdentifier(self: *Self, start: usize) Token {

        while (ascii.isAlphabetic(self.peek())
            or ascii.isDigit(self.peek())
            or self.peek() == '_')
                : (_ = self.advance()) {}
        return Token.init(self.identifierTag(start), start, self.current);
    }

    pub inline fn isAtEnd(self: Self) bool {
        return self.current >= self.source.len;
    }

    // This should probably be a source manager of some type. Gets the token from
    // the source information.
    pub fn getTokString(self: Self, token: Token) []const u8 {
        return self.source[token.loc.start..token.loc.end];
    }

    fn advance(self: *Self) u8 {
        self.current += 1;
        return self.source[self.current - 1];
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) {
            return false;
        }
        if (self.source[self.current] != expected) {
            return false;
        }

        self.current += 1;
        return true;
    }

    fn peek(self: Self) u8 {
        return self.source[self.current];
    }

    fn peekNext(self: Self) u8 {
        if (self.isAtEnd()) {
            return 0;
        }
        return self.source[self.current + 1];
    }

    fn skipWhitespace(self: *Self) void {
        while (self.current < self.source.len
            and ascii.isWhitespace(self.peek()))
            : (self.current += 1) {}
    }
};
