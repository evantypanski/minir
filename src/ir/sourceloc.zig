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
};
