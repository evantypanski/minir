const ir = @import("../ir.zig");
const std = @import("std");

pub fn IrVisitor(comptime ArgTy: type) type {
    return struct {
        visitProgram: VisitProgramFn = defaultVisitProgram,
        visitFunction: VisitFunctionFn = defaultVisitFunction,
        visitBasicBlock: VisitBasicBlockFn = defaultVisitBasicBlock,

        visitInstruction: VisitInstructionFn = defaultVisitInstruction,
        visitVarDecl: VisitVarDeclFn = defaultVisitVarDecl,
        visitFuncCall: VisitFuncCallFn = defaultVisitFuncCall,
        visitBranch: VisitBranchFn = defaultVisitBranch,

        visitValue: VisitValueFn = defaultVisitValue,
        visitVarAccess: VisitVarAccessFn = defaultVisitVarAccess,
        visitBinaryOp: VisitBinaryOpFn = defaultVisitBinaryOp,

        const Self = @This();

        // Containers
        const VisitProgramFn = *const fn(self: Self, arg: ArgTy, program: *ir.Program) void;
        const VisitFunctionFn = *const fn(self: Self, arg: ArgTy, function: *ir.Function) void;
        const VisitBasicBlockFn = *const fn(self: Self, arg: ArgTy, bb: *ir.BasicBlock) void;

        // Instructions
        const VisitInstructionFn = *const fn(self: Self, arg: ArgTy, instr: *ir.Instr) void;
        const VisitVarDeclFn = *const fn(self: Self, arg: ArgTy, decl: *ir.VarDecl) void;
        const VisitFuncCallFn = *const fn(self: Self, arg: ArgTy, call: *ir.FuncCall) void;
        const VisitBranchFn = *const fn(self: Self, arg: ArgTy, branch: *ir.Branch) void;

        // Values
        const VisitValueFn = *const fn(self: Self, arg: ArgTy, val: *ir.Value) void;
        const VisitVarAccessFn = *const fn(self: Self, arg: ArgTy, va: *ir.Value.VarAccess) void;
        const VisitBinaryOpFn = *const fn(self: Self, arg: ArgTy, bo: *ir.Value.BinaryOp) void;

        pub fn walkProgram(self: Self, arg: ArgTy, program: *ir.Program) void {
            for (program.functions) |*function| {
                self.visitFunction(self, arg, function);
            }
        }

        pub fn walkFunction(self: Self, arg: ArgTy, function: *ir.Function) void {
            for (function.bbs.items) |*bb| {
                self.visitBasicBlock(self, arg, bb);
            }
        }

        pub fn walkBasicBlock(self: Self, arg: ArgTy, bb: *ir.BasicBlock) void {
            for (bb.instructions.items) |*instr| {
                self.visitInstruction(self, arg, instr);
            }
        }

        pub fn walkInstruction(self: Self, arg: ArgTy, instr: *ir.Instr) void {
            switch (instr.*) {
                .debug => |*val| self.visitValue(self, arg, val),
                .id => |*decl| self.visitVarDecl(self, arg, decl),
                .call => |*call| self.visitFuncCall(self, arg, call),
                .branch => |*branch| self.visitBranch(self, arg, branch),
                // TODO: Ret can't take a value now so no visit method
                .ret => {},
            }
        }

        pub fn walkVarDecl(self: Self, arg: ArgTy, decl: *ir.VarDecl) void {
            if (decl.val) |*val| {
                self.visitValue(self, arg, val);
            }
        }

        // This could be split but the conditional/unconditional split isn't
        // that big of a deal.
        pub fn walkBranch(self: Self, arg: ArgTy, branch: *ir.Branch) void {
            switch (branch.*) {
                .unconditional => {},
                .conditional => |*conditional| {
                    self.visitValue(self, arg, &conditional.lhs);
                    if (conditional.rhs) |*rhs| {
                        self.visitValue(self, arg, rhs);
                    }
                },
            }
        }

        pub fn walkValue(self: Self, arg: ArgTy, val: *ir.Value) void {
            switch (val.*) {
                .access => |*va| self.visitVarAccess(self, arg, va),
                .binary => |*bo| self.visitBinaryOp(self, arg, bo),
                else => {},
            }
        }

        pub fn walkBinaryOp(self: Self, arg: ArgTy, bo: *ir.Value.BinaryOp) void {
            self.visitValue(self, arg, bo.lhs);
            self.visitValue(self, arg, bo.rhs);
        }

        pub fn defaultVisitProgram(self: Self, arg: ArgTy, program: *ir.Program) void {
            self.walkProgram(arg, program);
        }

        pub fn defaultVisitFunction(self: Self, arg: ArgTy, function: *ir.Function) void {
            self.walkFunction(arg, function);
        }

        pub fn defaultVisitBasicBlock(self: Self, arg: ArgTy, bb: *ir.BasicBlock) void {
            self.walkBasicBlock(arg, bb);
        }

        pub fn defaultVisitInstruction(self: Self, arg: ArgTy, instr: *ir.Instr) void {
            self.walkInstruction(arg, instr);
        }

        pub fn defaultVisitVarDecl(self: Self, arg: ArgTy, decl: *ir.VarDecl) void {
            self.walkVarDecl(arg, decl);
        }

        pub fn defaultVisitFuncCall(self: Self, arg: ArgTy, call: *ir.FuncCall) void {
            _ = self;
            _ = arg;
            _ = call;
        }

        pub fn defaultVisitBranch(self: Self, arg: ArgTy, branch: *ir.Branch) void {
            self.walkBranch(arg, branch);
        }

        pub fn defaultVisitValue(self: Self, arg: ArgTy, val: *ir.Value) void {
            self.walkValue(arg, val);
        }

        pub fn defaultVisitVarAccess(self: Self, arg: ArgTy, va: *ir.Value.VarAccess) void {
            _ = self;
            _ = arg;
            _ = va;
        }

        pub fn defaultVisitBinaryOp(self: Self, arg: ArgTy, bo: *ir.Value.BinaryOp) void {
            self.walkBinaryOp(arg, bo);
        }
    };
}
