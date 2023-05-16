const ir = @import("../ir.zig");
const std = @import("std");

pub fn IrVisitor(comptime ArgTy: type, comptime RetTy: type) type {
    return struct {
        visitProgram: VisitProgramFn = defaultVisitProgram,
        visitFunction: VisitFunctionFn = defaultVisitFunction,
        visitBasicBlock: VisitBasicBlockFn = defaultVisitBasicBlock,

        visitInstruction: VisitInstructionFn = defaultVisitInstruction,
        visitVarDecl: VisitVarDeclFn = defaultVisitVarDecl,
        visitBranch: VisitBranchFn = defaultVisitBranch,

        visitValue: VisitValueFn = defaultVisitValue,
        visitVarAccess: VisitVarAccessFn = defaultVisitVarAccess,
        visitBinaryOp: VisitBinaryOpFn = defaultVisitBinaryOp,
        visitFuncCall: VisitFuncCallFn = defaultVisitFuncCall,

        const Self = @This();

        // Containers
        const VisitProgramFn = *const fn(self: Self, arg: ArgTy, program: *ir.Program) RetTy;
        const VisitFunctionFn = *const fn(self: Self, arg: ArgTy, function: *ir.Function) RetTy;
        const VisitBasicBlockFn = *const fn(self: Self, arg: ArgTy, bb: *ir.BasicBlock) RetTy;

        // Instructions
        const VisitInstructionFn = *const fn(self: Self, arg: ArgTy, instr: *ir.Instr) RetTy;
        const VisitVarDeclFn = *const fn(self: Self, arg: ArgTy, decl: *ir.VarDecl) RetTy;
        const VisitBranchFn = *const fn(self: Self, arg: ArgTy, branch: *ir.Branch) RetTy;

        // Values
        const VisitValueFn = *const fn(self: Self, arg: ArgTy, val: *ir.Value) RetTy;
        const VisitVarAccessFn = *const fn(self: Self, arg: ArgTy, va: *ir.Value.VarAccess) RetTy;
        const VisitBinaryOpFn = *const fn(self: Self, arg: ArgTy, bo: *ir.Value.BinaryOp) RetTy;
        const VisitFuncCallFn = *const fn(self: Self, arg: ArgTy, call: *ir.Value.FuncCall) RetTy;

        pub fn walkProgram(self: Self, arg: ArgTy, program: *ir.Program) RetTy {
            for (program.functions.items) |*function| {
                try self.visitFunction(self, arg, function);
            }
        }

        pub fn walkFunction(self: Self, arg: ArgTy, function: *ir.Function) RetTy {
            for (function.bbs.items) |*bb| {
                try self.visitBasicBlock(self, arg, bb);
            }
        }

        pub fn walkBasicBlock(self: Self, arg: ArgTy, bb: *ir.BasicBlock) RetTy {
            for (bb.instructions.items) |*instr| {
                try self.visitInstruction(self, arg, instr);
            }
        }

        pub fn walkInstruction(self: Self, arg: ArgTy, instr: *ir.Instr) RetTy {
            switch (instr.*) {
                .debug => |*val| try self.visitValue(self, arg, val),
                .id => |*decl| try self.visitVarDecl(self, arg, decl),
                .branch => |*branch| try self.visitBranch(self, arg, branch),
                .value => |*value| try self.visitValue(self, arg, value),
                .ret => |*opt_value| {
                    if (opt_value.*) |*value| {
                        try self.visitValue(self, arg, value);
                    }
                }
            }
        }

        pub fn walkVarDecl(self: Self, arg: ArgTy, decl: *ir.VarDecl) RetTy {
            if (decl.val) |*val| {
                try self.visitValue(self, arg, val);
            }
        }

        // This could be split but the conditional/unconditional split isn't
        // that big of a deal.
        pub fn walkBranch(self: Self, arg: ArgTy, branch: *ir.Branch) RetTy {
            switch (branch.*) {
                .jump => {},
                .conditional => |*conditional| {
                    try self.visitValue(self, arg, &conditional.lhs);
                    if (conditional.rhs) |*rhs| {
                        try self.visitValue(self, arg, rhs);
                    }
                },
            }
        }

        pub fn walkValue(self: Self, arg: ArgTy, val: *ir.Value) RetTy {
            switch (val.*) {
                .access => |*va| try self.visitVarAccess(self, arg, va),
                .binary => |*bo| try self.visitBinaryOp(self, arg, bo),
                .call => |*call| try self.visitFuncCall(self, arg, call),
                else => {},
            }
        }

        pub fn walkBinaryOp(self: Self, arg: ArgTy, bo: *ir.Value.BinaryOp) RetTy {
            try self.visitValue(self, arg, bo.lhs);
            try self.visitValue(self, arg, bo.rhs);
        }

        pub fn walkFuncCall(self: Self, arg: ArgTy, call: *ir.Value.FuncCall) RetTy {
            if (call.arguments) |*arguments| {
                for (arguments.items) |*call_arg| {
                    try self.visitValue(self, arg, call_arg);
                }
            }
        }

        pub fn defaultVisitProgram(self: Self, arg: ArgTy, program: *ir.Program) RetTy {
            try self.walkProgram(arg, program);
        }

        pub fn defaultVisitFunction(self: Self, arg: ArgTy, function: *ir.Function) RetTy {
            try self.walkFunction(arg, function);
        }

        pub fn defaultVisitBasicBlock(self: Self, arg: ArgTy, bb: *ir.BasicBlock) RetTy {
            try self.walkBasicBlock(arg, bb);
        }

        pub fn defaultVisitInstruction(self: Self, arg: ArgTy, instr: *ir.Instr) RetTy {
            try self.walkInstruction(arg, instr);
        }

        pub fn defaultVisitVarDecl(self: Self, arg: ArgTy, decl: *ir.VarDecl) RetTy {
            try self.walkVarDecl(arg, decl);
        }

        pub fn defaultVisitBranch(self: Self, arg: ArgTy, branch: *ir.Branch) RetTy {
            try self.walkBranch(arg, branch);
        }

        pub fn defaultVisitValue(self: Self, arg: ArgTy, val: *ir.Value) RetTy {
            try self.walkValue(arg, val);
        }

        pub fn defaultVisitVarAccess(_: Self, _: ArgTy, _: *ir.Value.VarAccess) RetTy {
        }

        pub fn defaultVisitBinaryOp(self: Self, arg: ArgTy, bo: *ir.Value.BinaryOp) RetTy {
            try self.walkBinaryOp(arg, bo);
        }

        pub fn defaultVisitFuncCall(self: Self, arg: ArgTy, call: *ir.Value.FuncCall) RetTy {
            try self.walkFuncCall(arg, call);
        }
    };
}
