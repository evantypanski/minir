const Value = @import("value.zig").Value;

pub const OpCode = enum(u8) {
    const Self = @This();

    const value_size = @sizeOf(Value);

    ret,
    pop,
    constant,
    debug,
    add,
    sub,
    mul,
    div,

    not,
    and_,
    or_,
    // Comparisons
    eq,
    ne,
    gt,
    ge,
    lt,
    le,

    set,
    // Gets a variable at the next offset.
    // The immediate value is a signed byte for the offset from the current
    // frame. Negative values are parameters passed by caller, positive values
    // are locals in the current frame.
    get,

    // Unconditional jump
    jmp,
    // Jump if top of stack is true
    jmpt,

    // Call an absolute address
    call,

    // Allocate a pointer with the given size
    alloc,
    // Dereference a pointer with the given size
    deref,
    // Set the address at the top stack value to the next stack value
    heapset,

    pub fn numImmediates(self: Self) usize {
         return switch (self) {
             .jmp, .jmpt, .call => 2,
             .constant, .set, .get, .alloc, .deref, .heapset => 1,
             .ret, .debug, .add, .sub, .mul, .div, .eq, .ne, .gt, .ge, .lt, .le,
             .pop, .and_, .or_ => 0,
         };
    }

    pub fn stackEffect(self: Self) isize {
         return switch (self) {
             .constant, .get, .alloc => 1,
             .ret, .call, .jmp, .deref => 0,
             .debug, .add, .sub, .mul, .div, .eq, .ne, .gt, .ge, .lt, .le,
             .set, .jmpt, .pop, .and_, .or_ => -1,
             .heapset => -2,
         };
    }

    // If this updates the PC to an absolute value so the PC should not
    // be incremented after these instructions
    pub fn updatesPC(self: Self) bool {
        return switch (self) {
            .ret, .call, .jmp, .jmpt => true,
            else => false,
        };
    }
};
