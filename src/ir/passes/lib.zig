pub const IrVisitor = @import("util/visitor.zig").IrVisitor;
pub const ConstIrVisitor = @import("util/visitor.zig").ConstIrVisitor;

const pass = @import("util/pass.zig");
pub const Verifier = pass.Verifier;
pub const Modifier = pass.Modifier;
pub const Provider = pass.Provider;
pub const SimplePass = pass.SimplePass;
