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

    alloc,
    set,
    get,

    // Gets the number of variable offsets in this opcode. Must be less than
    // or equal to the number of immediates.
    pub fn numVars(self: Self) usize {
        return switch (self) {
            .set, .get => 1,
            .constant, .ret, .debug, .add, .sub, .mul, .div, .alloc => 0,
        };
    }

    pub fn numImmediates(self: Self) usize {
         return switch (self) {
             .constant, .set, .get => 1,
             .ret, .debug, .add, .sub, .mul, .div, .alloc => 0,
         };
    }

    pub fn stackEffect(self: Self) isize {
         return switch (self) {
             .constant, .get => 1,
             .ret, .alloc => 0,
             .debug, .add, .sub, .mul, .div, .set => -1,
         };
    }
};
