pub const InvalidBytecodeError = error {
    UnexpectedEnd,
    InvalidValueIndex,
    TooManyConstants,
    ReturnWithoutFunction,
};

pub const RuntimeError = error {
    StackOverflow,
    StackUnderflow,
    InvalidOperand,
    MaxFunctionDepth,
    ReachedEndNoReturn,
    NoValidFrame,
    InvalidStackIndex,

    // Type errors
    ExpectedInt,
    ExpectedFloat,
    ExpectedBool,
};
