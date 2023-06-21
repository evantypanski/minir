const Loc = @import("sourceloc.zig").Loc;

pub const Token = struct {
    const Self = @This();

    pub const Tag = enum {
        eof,
        lparen,
        rparen,
        lbrace,
        rbrace,
        arrow,
        at,
        colon,
        comma,
        identifier,
        num,

        eq,
        eq_eq,
        plus,
        minus,
        star,
        slash,
        amp_amp,
        pipe_pipe,
        less,
        less_eq,
        greater,
        greater_eq,

        // Keywords
        func,
        debug,
        let,
        true_,
        false_,
        undefined_,
        ret,
        // Branch keywords
        br,
        brz,
        bre,
        brl,
        brle,
        brg,
        brge,

        // Default value of "undefined" token. Should not appear when lexing
        // normally.
        none,
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
        return Self.init(.none, 0, 0);
    }

    pub fn isValid(self: Self) bool {
        return self.tag != .none;
    }

    pub fn isOp(self: Self) bool {
        return switch(self.tag) {
            .eq, .plus, .minus, .star, .slash, .amp_amp, .pipe_pipe,
            .less, .less_eq, .greater, .greater_eq => true,
            else => false,
        };
    }
};
