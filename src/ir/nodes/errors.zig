//! Common errors for all nodes, since there is no overarching Node yet.

pub const NodeError = error {
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

