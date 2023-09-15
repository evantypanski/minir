// Like Zig compiler with start/end because it's just one stream.
pub const Loc = struct {
    start: usize,
    end: usize,

    pub fn init(start: usize, end: usize) Loc {
        return .{
            .start = start,
            .end = end,
        };
    }

    pub fn default() Loc {
        return .{
            .start = 0,
            .end = 0,
        };
    }

    // TODO: Check if lhs is earlier in file than rhs
    pub fn combine(lhs_loc: Loc, rhs_loc: Loc) Loc {
        return Loc.init(lhs_loc.start, rhs_loc.end);
    }
};
