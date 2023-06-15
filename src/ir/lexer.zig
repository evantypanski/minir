const std = @import("std");
const ascii = std.ascii;

const Token = @import("token.zig").Token;
const LexError = @import("errors.zig").LexError;

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
            return Token.init(.eof, self.source.len - 1, self.source.len - 1);
        }

        var c = self.advance();

        if (ascii.isAlphabetic(c) or c == '_') {
            return self.lexIdentifier(start);
        } else if (ascii.isDigit(c)) {
            return self.lexNumber(start);
        }

        return switch (c) {
            '(' => Token.init(.lparen, start, self.current),
            ')' => Token.init(.rparen, start, self.current),
            '{' => Token.init(.lbrace, start, self.current),
            '}' => Token.init(.rbrace, start, self.current),
            '@' => Token.init(.at, start, self.current),
            ':' => Token.init(.colon, start, self.current),
            ',' => Token.init(.comma, start, self.current),
            '=' => if (self.match('='))
                        Token.init(.eq_eq, start, self.current)
                    else
                        Token.init(.eq, start, self.current),
            '+' => Token.init(.plus, start, self.current),
            '-' => if (self.match('>'))
                        Token.init(.arrow, start, self.current)
                    else
                        Token.init(.minus, start, self.current),
            '*' => Token.init(.star, start, self.current),
            '/' => Token.init(.slash, start, self.current),
            '&' => if (self.match('&'))
                        Token.init(.amp_amp, start, self.current)
                    else
                        return error.Unexpected,
            '|' => if (self.match('|'))
                        Token.init(.pipe_pipe, start, self.current)
                    else
                        return error.Unexpected,
            '<' => if (self.match('='))
                        Token.init(.greater_eq, start, self.current)
                    else
                        Token.init(.greater, start, self.current),
            '>' => if (self.match('='))
                        Token.init(.less_eq, start, self.current)
                    else
                        Token.init(.less, start, self.current),

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

        return Token.init(.num, start, self.current);
    }

    /// Gets the tag associated with the current token. Efficiently matches
    /// keywords :)
    ///
    /// It's pretty overkill with so few. But oh well. Grabbed this tiny trie
    /// impl from crafting interpreters.
    fn identifierTag(self: Self, start: usize) Token.Tag {
        const token_len = self.current - start;
        switch (self.source[start]) {
            'f' => return self.checkKeyword(start + 1, 3, "unc", .func),
            'd' => return self.checkKeyword(start + 1, 4, "ebug", .debug),
            // Just do branches here because why not. This is a mess. Oops.
            'b' => if (token_len >= 2) {
                    switch (self.source[start + 1]) {
                        'r' => {
                            if (token_len == 2)
                                return .br
                            else
                                return switch (self.source[start + 2]) {
                                    'z' => .brz,
                                    'e' => .bre,
                                    'l' => if (token_len > 3)
                                                self.checkKeyword(start + 2, 2,
                                                        "le", .brle)
                                            else
                                                .brl,
                                    'g' => if (token_len > 3)
                                                self.checkKeyword(start + 2, 2,
                                                        "ge", .brge)
                                            else
                                                .brg,
                                    else => .identifier,
                                };
                        },
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
            and std.mem.eql(u8, self.source[start..self.current], rest)) {
            return tag;
        }

        return .identifier;
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
