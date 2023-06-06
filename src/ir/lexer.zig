const std = @import("std");

const Token = @import("token.zig").Token;

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

    pub fn lex(self: *Self) Token {
        const start = self.current;

        if (self.isAtEnd()) {
            // EOF token has the last character as its slice
            return Token.init(.EOF, &self.source[self.source.len - 1..]);
        }

        var c = self.advance();
        return switch (c) {
            '+' => Token.init(.PLUS, &self.source[start..self.current]),
            '-' => Token.init(.MINUS, &self.source[start..self.current]),
            '=' => Token.init(.EQ, &self.source[start..self.current]),
            '>' => if (self.match('='))
                        Token.init(.GE, &self.source[start..self.current])
                    else
                        Token.init(.GT, &self.source[start..self.current]),

            // TODO: Error token?
            else => Token.init(.EOF, &self.source[self.source.len - 1..]),
        };

        //return Token.init(.DEBUG, &self.source[start..start + 1]);
    }

    pub inline fn isAtEnd(self: Self) bool {
        return self.current >= self.source.len;
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
};
