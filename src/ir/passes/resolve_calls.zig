const std = @import("std");

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const BasicBlockBuilder = @import("../nodes/basic_block.zig").BasicBlockBuilder;
const Stmt = @import("../nodes/statement.zig").Stmt;
const FuncCall = @import("../nodes/value.zig").FuncCall;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;
const Diagnostics = @import("../diagnostics_engine.zig").Diagnostics;
const ResolveError = @import("../errors.zig").ResolveError;

pub const ResolveCallsPass = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, ResolveError!void);

    allocator: std.mem.Allocator,
    diag: Diagnostics,
    resolved: std.StringHashMap(*Decl),

    pub fn init(allocator: std.mem.Allocator, diag: Diagnostics) Self {
        return .{
            .allocator = allocator,
            .diag = diag,
            .resolved = std.StringHashMap(*Decl).init(allocator),
        };
    }

    pub const ResolveVisitor = VisitorTy {
        .visitFuncCall = visitFuncCall,
    };

    pub fn execute(self: *Self, program: *Program) ResolveError!void {
        for (program.decls) |*decl| {
            const name = decl.name();
            if (self.resolved.contains(name)) {
                return error.NameConflict;
            }

            self.resolved.put(name, decl) catch return error.MemoryError;
        }

        try ResolveVisitor.visitProgram(ResolveVisitor, self, program);
    }

    pub fn visitFuncCall(
        visitor: VisitorTy,
        self: *Self,
        call: *FuncCall
    ) ResolveError!void {
        // Don't re-resolve if it's already been resolved.
        if (call.resolved != null) {
            return;
        }

        const decl = self.resolved.get(call.function);
        if (decl == null) {
            return error.NoSuchFunction;
        }

        call.resolved = decl;

        try visitor.walkFuncCall(self, call);
    }
};
