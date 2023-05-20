pub const OpCode = enum(u8) {
    const Self = @This();

    ret,
    constant,
    debug,
    add,
    sub,
    mul,
    div,

    pub fn numImmediates(self: Self) usize {
         return switch (self) {
             .constant => 1,
             .ret, .debug, .add, .sub, .mul, .div => 0,
         };
    }

    pub fn stackEffect(self: Self) isize {
         return switch (self) {
             .constant => 1,
             .ret => 0,
             .debug, .add, .sub, .mul, .div => -1,
         };
    }
};
