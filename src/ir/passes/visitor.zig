const std = @import("std");

const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const instruction = @import("../nodes/instruction.zig");
const Instr = instruction.Instr;
const Branch = instruction.Branch;
const VarDecl = instruction.VarDecl;
const Function = @import("../nodes/function.zig").Function;
const Program = @import("../nodes/program.zig").Program;
const Value = @import("../nodes/value.zig").Value;

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
        const VisitProgramFn = *const fn(self: Self, arg: ArgTy, program: *Program) RetTy;
        const VisitFunctionFn = *const fn(self: Self, arg: ArgTy, function: *Function) RetTy;
        const VisitBasicBlockFn = *const fn(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy;

        // Instructions
        const VisitInstructionFn = *const fn(self: Self, arg: ArgTy, instr: *Instr) RetTy;
        const VisitVarDeclFn = *const fn(self: Self, arg: ArgTy, decl: *VarDecl) RetTy;
        const VisitBranchFn = *const fn(self: Self, arg: ArgTy, branch: *Branch) RetTy;

        // Values
        const VisitValueFn = *const fn(self: Self, arg: ArgTy, val: *Value) RetTy;
        const VisitVarAccessFn = *const fn(self: Self, arg: ArgTy, va: *Value.VarAccess) RetTy;
        const VisitBinaryOpFn = *const fn(self: Self, arg: ArgTy, bo: *Value.BinaryOp) RetTy;
        const VisitFuncCallFn = *const fn(self: Self, arg: ArgTy, call: *Value.FuncCall) RetTy;

        pub fn walkProgram(self: Self, arg: ArgTy, program: *Program) RetTy {
            for (program.functions) |*function| {
                try self.visitFunction(self, arg, function);
            }
        }

        pub fn walkFunction(self: Self, arg: ArgTy, function: *Function) RetTy {
            for (function.bbs) |*bb| {
                try self.visitBasicBlock(self, arg, bb);
            }
        }

        pub fn walkBasicBlock(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy {
            for (bb.instructions) |*instr| {
                try self.visitInstruction(self, arg, instr);
            }
        }

        pub fn walkInstruction(self: Self, arg: ArgTy, instr: *Instr) RetTy {
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

        pub fn walkVarDecl(self: Self, arg: ArgTy, decl: *VarDecl) RetTy {
            if (decl.val) |*val| {
                try self.visitValue(self, arg, val);
            }
        }

        // This could be split but the conditional/unconditional split isn't
        // that big of a deal.
        pub fn walkBranch(self: Self, arg: ArgTy, branch: *Branch) RetTy {
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

        pub fn walkValue(self: Self, arg: ArgTy, val: *Value) RetTy {
            switch (val.*) {
                .access => |*va| try self.visitVarAccess(self, arg, va),
                .binary => |*bo| try self.visitBinaryOp(self, arg, bo),
                .call => |*call| try self.visitFuncCall(self, arg, call),
                else => {},
            }
        }

        pub fn walkBinaryOp(self: Self, arg: ArgTy, bo: *Value.BinaryOp) RetTy {
            try self.visitValue(self, arg, bo.lhs);
            try self.visitValue(self, arg, bo.rhs);
        }

        pub fn walkFuncCall(self: Self, arg: ArgTy, call: *Value.FuncCall) RetTy {
            for (call.arguments) |*call_arg| {
                try self.visitValue(self, arg, call_arg);
            }
        }

        pub fn defaultVisitProgram(self: Self, arg: ArgTy, program: *Program) RetTy {
            try self.walkProgram(arg, program);
        }

        pub fn defaultVisitFunction(self: Self, arg: ArgTy, function: *Function) RetTy {
            try self.walkFunction(arg, function);
        }

        pub fn defaultVisitBasicBlock(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy {
            try self.walkBasicBlock(arg, bb);
        }

        pub fn defaultVisitInstruction(self: Self, arg: ArgTy, instr: *Instr) RetTy {
            try self.walkInstruction(arg, instr);
        }

        pub fn defaultVisitVarDecl(self: Self, arg: ArgTy, decl: *VarDecl) RetTy {
            try self.walkVarDecl(arg, decl);
        }

        pub fn defaultVisitBranch(self: Self, arg: ArgTy, branch: *Branch) RetTy {
            try self.walkBranch(arg, branch);
        }

        pub fn defaultVisitValue(self: Self, arg: ArgTy, val: *Value) RetTy {
            try self.walkValue(arg, val);
        }

        pub fn defaultVisitVarAccess(_: Self, _: ArgTy, _: *Value.VarAccess) RetTy {
        }

        pub fn defaultVisitBinaryOp(self: Self, arg: ArgTy, bo: *Value.BinaryOp) RetTy {
            try self.walkBinaryOp(arg, bo);
        }

        pub fn defaultVisitFuncCall(self: Self, arg: ArgTy, call: *Value.FuncCall) RetTy {
            try self.walkFuncCall(arg, call);
        }
    };
}