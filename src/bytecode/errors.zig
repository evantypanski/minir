pub const InvalidBytecodeError = error {
    UnexpectedEnd,
    InvalidValueIndex,
    TooManyConstants,
};

pub const RuntimeError = error {
    StackOverflow,
    StackUnderflow,
    InvalidOperand,

    // Type errors
    ExpectedInt,
    ExpectedFloat,
};
