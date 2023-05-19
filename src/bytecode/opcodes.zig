pub const OpCode = enum(u8) {
    const Self = @This();

    ret,
    constant,

    pub fn numImmediates(self: Self) usize {
         return switch (self) {
             .ret => 0,
             .constant => 1,
         };
    }
};
