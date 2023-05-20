pub const ValueKind = enum {
    undef,
    int,
    float,
};

pub const Value = union(ValueKind) {
    undef,
    int: i32,
    float: f32,
};
