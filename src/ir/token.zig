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
        semi,
        comma,
        identifier,
        num,

        bang,

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

        // Invalid token
        err,
    };

    pub const Keyword = enum {
        func,
        alloc,
        debug,
        let,
        true_,
        false_,
        undefined_,
        ret,
        float,
        int,
        boolean,
        none,

        // Branch keywords
        br,
        brc,

    };

    tag: Tag,
    kw: ?Keyword,
    loc: Loc,

    pub fn init(tag: Tag, start: usize, end: usize) Self {
        return .{
            .tag = tag,
            .kw = null,
            .loc = .{
                .start = start,
                .end = end,
            },
        };
    }

    /// All keywords are identifiers, so that is given.
    pub fn initKw(kw: Keyword, start: usize, end: usize) Self {
        return .{
            .tag = .identifier,
            .kw = kw,
            .loc = .{
                .start = start,
                .end = end,
            },
        };
    }

    pub fn isValid(self: Self) bool {
        return self.tag != .err;
    }

    pub fn isUnaryOp(self: Self) bool {
        return switch(self.tag) {
            .bang, .star => true,
            else => false,
        };
    }

    pub fn isBinaryOp(self: Self) bool {
        return switch(self.tag) {
            .eq, .eq_eq, .plus, .minus, .star, .slash, .amp_amp, .pipe_pipe,
            .less, .less_eq, .greater, .greater_eq => true,
            else => false,
        };
    }

    pub fn isBranch(self: Self) bool {
        return if (self.kw) |kw|
            switch (kw) {
                .br, .brc => true,
                else => false,
            }
        else
            false;
    }
};
