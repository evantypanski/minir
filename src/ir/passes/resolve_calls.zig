const std = @import("std");

const Allocator = std.mem.Allocator;

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const builtins = @import("../nodes/decl.zig").builtins;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const FuncCall = @import("../nodes/value.zig").FuncCall;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;

pub const ResolveCallsPass = struct {
    pub const Error = error {
        NameConflict,
        NoSuchFunction,
    } || Allocator.Error;

    const Self = @This();
    const VisitorTy = IrVisitor(*Self, Error!void);

    allocator: Allocator,
    diag: Diagnostics,
    resolved: std.StringHashMap(*Decl),

    pub fn init(allocator: Allocator, diag: Diagnostics) Self {
        return .{
            .allocator = allocator,
            .diag = diag,
            .resolved = std.StringHashMap(*Decl).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.resolved.clearAndFree();
    }

    pub const ResolveVisitor = VisitorTy {
        .visitFuncCall = visitFuncCall,
    };

    pub fn execute(self: *Self, program: *Program) Error!void {
        for (program.decls) |*decl| {
            const name = decl.name();
            if (self.resolved.contains(name)) {
                return error.NameConflict;
            }

            try self.resolved.put(name, decl);
        }

        try ResolveVisitor.visitProgram(ResolveVisitor, self, program);
    }

    pub fn visitFuncCall(
        visitor: VisitorTy,
        self: *Self,
        call: *FuncCall
    ) Error!void {
        // Don't re-resolve if it's already been resolved.
        if (call.resolved != null) {
            return;
        }

        const decl = builtins.get(call.name()) orelse
            self.resolved.get(call.name());

        if (decl == null) {
            return error.NoSuchFunction;
        }

        call.resolved = decl;

        try visitor.walkFuncCall(self, call);
    }
};
