pub const Token = struct {
    const Self = @This();

    pub const Tag = enum {
        EOF,
        LPAREN,
        RPAREN,
        LBRACE,
        RBRACE,
        ARROW,
        AT,
        COLON,
        COMMA,
        IDENTIFIER,
        NUM,

        EQ,
        EQ_EQ,
        PLUS,
        MINUS,
        STAR,
        SLASH,
        AMP_AMP,
        PIPE_PIPE,
        LESS,
        LESS_EQ,
        GREATER,
        GREATER_EQ,

        // Keywords
        FN,
        DEBUG,
        // Branch keywords
        BR,
        BRZ,
        BRE,
        BRL,
        BRLE,
        BRG,
        BRGE,

        // Default value of "undefined" token. Should not appear when lexing
        // normally.
        NONE,
    };

    // Like Zig compiler with start/end because it's just one stream.
    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    tag: Tag,
    loc: Loc,

    pub fn init(tag: Tag, start: usize, end: usize) Self {
        return .{
            .tag = tag,
            .loc = .{
                .start = start,
                .end = end,
            },
        };
    }

    pub fn none() Self {
        return Self.init(.NONE, 0, 0);
    }

    pub fn isValid(self: Self) bool {
        return self.tag != .NONE;
    }

    pub fn isOp(self: Self) bool {
        return switch(self.tag) {
            .EQ, .PLUS, .MINUS, .STAR, .SLASH, .AMP_AMP, .PIPE_PIPE,
            .LESS, .LESS_EQ, .GREATER, .GREATER_EQ => true,
            else => false,
        };
    }
};
