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
    NotAPtr,
    NotABool,
    ExpectedTerminator,
    UnexpectedTerminator,
    DuplicateMain,
    NoMainFunction,
    NotAnOperator,
    InvalidTypeName,
    NotABranch,
};

pub const IrError = InterpError || NodeError || HeapError;

pub const TokenParseError = error {
    Unexpected,
    ExpectedNumber,
    Expected,
    MemoryError,
    NotANumber,
    NotALiteral,
    NotABoolean,
    KeywordInvalidIdentifier,
};

pub const LexError = error {
    Unexpected,
};

const TypecheckErrorInner = error{
    MapError,
    ParamWithoutType,
    TooManyErrors,
    NakedVarDecl,
    CannotEvaluateType,
    Unimplemented,
    IncompatibleTypes,
    CannotResolve,
    InvalidType,
    BadArity,
    Unresolved,
};

pub const ResolveError = error{
    MemoryError,
    NameConflict,
    NoSuchFunction,
};

pub const HeapError = error{
    Bad,
};

pub const TypecheckError = TypecheckErrorInner || ResolveError;

pub const ParseError = TokenParseError || NodeError || LexError;

/// Gets the format string for a given error. Any unimplemented errors expect
/// three format string arguments: the file name, the line number, and the
/// code snippet.
pub fn getErrStr(comptime err: anyerror) ?[]const u8 {
    return switch (err) {
        error.InvalidType => "{s} is an invalid type for '{s}'",
        error.IncompatibleTypes => "type {s} of '{s}' is incompatible with type {s} of '{s}'",
        error.Expected => "expected '{s}' token",
        error.NotABranch => "'{s}' is not a branch keyword",
        error.NotANumber => "'{s}' is not a valid number",
        error.BadArity => "call to '{s}' expected {} argument(s); found {}",
        error.Unresolved => "unresolved variable access to '{s}'",
        error.KeywordInvalidIdentifier => "'{s}' is a keyword and cannot be used as an identifier",
        else => null,
    };
}
