const TokenType = enum {
    EOF,
    LPAREN,
    RPAREN,
    LBRACE,
    RBRACE,
    ARROW,
    AT,
    IDENTIFIER,

    PLUS,
    MINUS,
    EQ,
    GE,
    GT,

    // Keywords
    FN,
    DEBUG
};

pub const Token = struct {
    const Self = @This();

    ty: TokenType,
    // This may change if we want context from the source better.
    slice: *const []u8,

    pub fn init(ty: TokenType, slice: *const []u8) Self {
        return .{
            .ty = ty,
            .slice = slice,
        };
    }
};
