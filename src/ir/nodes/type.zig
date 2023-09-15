pub const Type = enum {
    int,
    float,
    boolean,
    // void but avoiding name conflicts is good :)
    none,
    // this is only applied if we cannot determine the type
    err,

    /// A wrapper around type equality so that error types are equal to
    /// all other types. This helps avoid double diagnosing an error.
    pub fn eq(self: Type, other: Type) bool {
        if (self == .err or other == .err) {
            return true;
        }

        return self == other;
    }
};
