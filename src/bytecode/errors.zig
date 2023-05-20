pub const InvalidBytecodeError = error {
    UnexpectedEnd,
    InvalidValueIndex,
};

pub const RuntimeError = error {
    StackOverflow,
    StackUnderflow,
};
