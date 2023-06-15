pub const InterpError = error{
    OperandError,
    InvalidInt,
    InvalidFloat,
    InvalidBool,
    CannotEvaluateUndefined,
    VariableUndefined,
    InvalidLHSAssign,
    LabelNoIndex,
    TypeError,
    NoSuchFunction,
    ExpectedNumifiedAccess,
    CallError,
    ExpectedReturn,
    FrameError,
    StackError,
};

pub const NodeError = error{
    NotAnInt,
    NotAFloat,
    NotABool,
    ExpectedTerminator,
    UnexpectedTerminator,
    DuplicateMain,
    NoMainFunction,
    NotAnOperator,
};

pub const IrError = InterpError || NodeError;

pub const TokenParseError = error {
    Unexpected,
    ExpectedNumber,
    ExpectedAt,
    ExpectedIdentifier,
    ExpectedLParen,
    ExpectedRParen,
    ExpectedArrow,
    ExpectedLBrace,
    ExpectedRBrace,
    ExpectedKeywordFunc,
    MemoryError,
    NotANumber,
};

pub const LexError = error {
    Unexpected,
};

pub const ParseError = TokenParseError || NodeError || LexError;
