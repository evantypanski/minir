const std = @import("std");

const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const statement = @import("../nodes/statement.zig");
const Stmt = statement.Stmt;
const Branch = statement.Branch;
const VarDecl = statement.VarDecl;
const Decl = @import("../nodes/decl.zig").Decl;
const Function = @import("../nodes/decl.zig").Function;
const Program = @import("../nodes/program.zig").Program;
const Value = @import("../nodes/value.zig").Value;

pub fn IrVisitor(comptime ArgTy: type, comptime RetTy: type) type {
    return struct {
        visitProgram: VisitProgramFn = defaultVisitProgram,
        visitDecl: VisitDeclFn = defaultVisitDecl,
        visitFunction: VisitFunctionFn = defaultVisitFunction,
        visitBBFunction: VisitBBFunctionFn = defaultVisitBBFunction,
        visitBasicBlock: VisitBasicBlockFn = defaultVisitBasicBlock,

        visitStatement: VisitStatementFn = defaultVisitStatement,
        visitVarDecl: VisitVarDeclFn = defaultVisitVarDecl,
        visitBranch: VisitBranchFn = defaultVisitBranch,

        visitValue: VisitValueFn = defaultVisitValue,
        visitUndef: VisitUndefFn = defaultVisitUndef,
        visitVarAccess: VisitVarAccessFn = defaultVisitVarAccess,
        visitInt: VisitIntFn = defaultVisitInt,
        visitFloat: VisitFloatFn = defaultVisitFloat,
        visitBool: VisitBoolFn = defaultVisitBool,
        visitBinaryOp: VisitBinaryOpFn = defaultVisitBinaryOp,
        visitFuncCall: VisitFuncCallFn = defaultVisitFuncCall,

        const Self = @This();

        // Containers
        const VisitProgramFn = *const fn(self: Self, arg: ArgTy, program: *Program) RetTy;
        const VisitDeclFn = *const fn(self: Self, arg: ArgTy, decl: *Decl) RetTy;
        const VisitFunctionFn = *const fn(self: Self, arg: ArgTy, function: *Function(Stmt)) RetTy;
        const VisitBBFunctionFn = *const fn(self: Self, arg: ArgTy, bb_function: *Function(BasicBlock)) RetTy;
        const VisitBasicBlockFn = *const fn(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy;

        // Statements
        const VisitStatementFn = *const fn(self: Self, arg: ArgTy, stmt: *Stmt) RetTy;
        const VisitVarDeclFn = *const fn(self: Self, arg: ArgTy, decl: *VarDecl) RetTy;
        const VisitBranchFn = *const fn(self: Self, arg: ArgTy, branch: *Branch) RetTy;

        // Values
        const VisitValueFn = *const fn(self: Self, arg: ArgTy, val: *Value) RetTy;
        const VisitUndefFn = *const fn(self: Self, arg: ArgTy) RetTy;
        const VisitVarAccessFn = *const fn(self: Self, arg: ArgTy, va: *Value.VarAccess) RetTy;
        const VisitIntFn = *const fn(self: Self, arg: ArgTy, i: *i32) RetTy;
        const VisitFloatFn = *const fn(self: Self, arg: ArgTy, f: *f32) RetTy;
        const VisitBoolFn = *const fn(self: Self, arg: ArgTy, b: *u1) RetTy;
        const VisitBinaryOpFn = *const fn(self: Self, arg: ArgTy, bo: *Value.BinaryOp) RetTy;
        const VisitFuncCallFn = *const fn(self: Self, arg: ArgTy, call: *Value.FuncCall) RetTy;

        pub fn walkProgram(self: Self, arg: ArgTy, program: *Program) RetTy {
            for (program.decls) |*function| {
                try self.visitDecl(self, arg, function);
            }
        }

        pub fn walkDecl(self: Self, arg: ArgTy, decl: *Decl) RetTy {
            switch (decl.*) {
                .function => |*func| try self.visitFunction(self, arg, func),
                .bb_function => |*bb_func| try self.visitBBFunction(self, arg, bb_func),
            }
        }

        pub fn walkFunction(self: Self, arg: ArgTy, function: *Function(Stmt)) RetTy {
            for (function.elements) |*stmt| {
                try self.visitStatement(self, arg, stmt);
            }
        }

        pub fn walkBBFunction(self: Self, arg: ArgTy, function: *Function(BasicBlock)) RetTy {
            for (function.elements) |*bb| {
                try self.visitBasicBlock(self, arg, bb);
            }
        }

        pub fn walkBasicBlock(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy {
            for (bb.statements) |*stmt| {
                try self.visitStatement(self, arg, stmt);
            }
        }

        pub fn walkStatement(self: Self, arg: ArgTy, stmt: *Stmt) RetTy {
            switch (stmt.*.stmt_kind) {
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
                .undef => try self.visitUndef(self, arg),
                .access => |*va| try self.visitVarAccess(self, arg, va),
                .int => |*i| try self.visitInt(self, arg, i),
                .float => |*f| try self.visitFloat(self, arg, f),
                .bool => |*b| try self.visitBool(self, arg, b),
                .binary => |*bo| try self.visitBinaryOp(self, arg, bo),
                .call => |*call| try self.visitFuncCall(self, arg, call),
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

        pub fn defaultVisitDecl(self: Self, arg: ArgTy, decl: *Decl) RetTy {
            try self.walkDecl(arg, decl);
        }

        pub fn defaultVisitFunction(self: Self, arg: ArgTy, function: *Function(Stmt)) RetTy {
            try self.walkFunction(arg, function);
        }

        pub fn defaultVisitBBFunction(self: Self, arg: ArgTy, bb_function: *Function(BasicBlock)) RetTy {
            try self.walkBBFunction(arg, bb_function);
        }

        pub fn defaultVisitBasicBlock(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy {
            try self.walkBasicBlock(arg, bb);
        }

        pub fn defaultVisitStatement(self: Self, arg: ArgTy, stmt: *Stmt) RetTy {
            try self.walkStatement(arg, stmt);
        }

        pub fn defaultVisitUndef(self: Self, arg: ArgTy) RetTy {
            _ = self;
            _ = arg;
        }

        pub fn defaultVisitVarDecl(self: Self, arg: ArgTy, decl: *VarDecl) RetTy {
            try self.walkVarDecl(arg, decl);
        }

        pub fn defaultVisitInt(self: Self, arg: ArgTy, i: *i32) RetTy {
            _ = self;
            _ = arg;
            _ = i;
        }

        pub fn defaultVisitFloat(self: Self, arg: ArgTy, f: *f32) RetTy {
            _ = self;
            _ = arg;
            _ = f;
        }

        pub fn defaultVisitBool(self: Self, arg: ArgTy, b: *u1) RetTy {
            _ = self;
            _ = arg;
            _ = b;
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
