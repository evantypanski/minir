const std = @import("std");

const Allocator = std.mem.Allocator;
const Program = @import("../nodes/program.zig").Program;

pub const PassKind = enum {
    verifier,
    modifier,
    provider,
};

fn VerifierRunTy(PassTy: type, Error: type) type {
    return *const fn (self: *PassTy, program: *const Program) Error!void;
}

pub fn Verifier(
    PassTy: type, Error: type, dependencies: []const type,
    init: *const fn (args: anytype) PassTy,
    run: VerifierRunTy(PassTy, Error),
) type {
    return Pass(
        PassTy, Error!void, VerifierRunTy(PassTy, Error), dependencies,
        init, run, .verifier
    );
}

fn ModifierRunTy(PassTy: type, Error: type) type {
    return *const fn (self: *PassTy, program: *Program) Error!void;
}

pub fn Modifier(
    PassTy: type, Error: type, dependencies: []const type,
    init: *const fn (args: anytype) PassTy,
    run: ModifierRunTy(PassTy, Error),
) type {
    return Pass(
        PassTy, Error!void, ModifierRunTy(PassTy, Error),
        dependencies, init, run, .modifier
    );
}

fn ProviderRunTy(PassTy: type, Error: type, RetTy: type) type {
    return *const fn (self: *PassTy, program: *const Program) Error!RetTy;
}

pub fn Provider(
    PassTy: type, Error: type, RetTy: type, dependencies: []const type,
    init: *const fn (args: anytype) PassTy,
    run: ProviderRunTy(PassTy, Error, RetTy),
) type {
    return Pass(
        PassTy, Error!RetTy, ProviderRunTy(PassTy, Error, RetTy),
        dependencies, init, run, .provider
    );
}

// TODO: Try to clean up these arguments a bit. I'd rather not specify RetTy
// multiple times or have some other way to get that.
fn Pass(
    PassTy: type, RetTy: type, RunFnTy: type, dependencies_: []const type,
    init_: *const fn (args: anytype) PassTy,
    run_: RunFnTy, pass_kind_: PassKind,
) type {
    return struct {
        const Self = @This();

        const run = run_;
        pub const init: *const fn (args: anytype) PassTy = init_;
        pub const dependencies: []const type = dependencies_;
        pub const RetType: type = RetTy;
        pub const pass_kind: PassKind = pass_kind_;

        result: ?RetTy = null,

        pub fn get(self: *Self, pass: *PassTy, program: *Program) RetTy {
            if (self.result) |res| {
                return res;
            }

            self.result = run(pass, program);
            return self.result.?;
        }
    };
}
