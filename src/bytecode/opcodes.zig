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
             .ret, .debug, .add, .sub, .mul, .div => 0,
             .constant => 1,
         };
    }

    pub fn numPops(self: Self) usize {
         return switch (self) {
             .ret, .constant => 0,
             .debug => 1,
             .add, .sub, .mul, .div => 2,
         };
    }
};
