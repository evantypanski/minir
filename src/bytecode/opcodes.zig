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

    gt,

    alloc,
    set,
    get,

    // Jump if false
    jmpf,

    pub fn numImmediates(self: Self) usize {
         return switch (self) {
             .jmpf => 2,
             .constant, .set, .get => 1,
             .ret, .debug, .add, .sub, .mul, .div, .gt, .alloc => 0,
         };
    }

    pub fn stackEffect(self: Self) isize {
         return switch (self) {
             .constant, .get => 1,
             .ret, .alloc => 0,
             .debug, .add, .sub, .mul, .div, .gt, .set, .jmpf => -1,
         };
    }
};
