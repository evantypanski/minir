pub const ValueKind = enum {
    int,
    float,
};

pub const Value = union(ValueKind) {
    int: i32,
    float: f32,
};
