const Value = @import("value.zig").Value;

pub const OpCode = enum(u8) {
    const Self = @This();

    const value_size = @sizeOf(Value);

    ret,
    constant,
    debug,
    add,
    sub,
    mul,
    div,

    // Comparisons
    eq,
    ne,
    gt,
    ge,
    lt,
    le,

    alloc,
    set,
    get,

    // Jump if false
    jmpf,

    // Call an absolute address
    call,

    pub fn numImmediates(self: Self) usize {
         return switch (self) {
             .jmpf, .call => 2,
             .constant, .set, .get => 1,
             .ret, .debug, .add, .sub, .mul, .div, .eq, .ne, .gt, .ge, .lt, .le,
             .alloc => 0,
         };
    }

    pub fn stackEffect(self: Self) isize {
         return switch (self) {
             .constant, .get => 1,
             .ret, .alloc, .call => 0,
             .debug, .add, .sub, .mul, .div, .eq, .ne, .gt, .ge, .lt, .le,
             .set, .jmpf => -1,
         };
    }

    // If this updates the PC to an absolute value so the PC should not
    // be incremented after these instructions
    pub fn updatesPC(self: Self) bool {
        return switch (self) {
            .ret, .call => true,
            else => false,
        };
    }
};
