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
    InvalidValue,
    WriterError,
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
    InvalidTypeName,
    NotABranch,
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
    ExpectedComma,
    ExpectedColon,
    MemoryError,
    NotANumber,
    NotALiteral,
    NotABoolean,
};

pub const LexError = error {
    Unexpected,
};

pub const TypecheckError = error{
    MapError,
    ParamWithoutType,
    TooManyErrors,
    NakedVarDecl,
    CannotEvaluateType,
    Unimplemented,
    IncompatibleTypes,
    CannotResolve,
};

pub const ParseError = TokenParseError || NodeError || LexError;
