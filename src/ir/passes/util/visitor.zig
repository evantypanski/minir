const std = @import("std");

const BasicBlock = @import("../../nodes/basic_block.zig").BasicBlock;
const statement = @import("../../nodes/statement.zig");
const Stmt = statement.Stmt;
const Branch = statement.Branch;
const VarDecl = statement.VarDecl;
const Decl = @import("../../nodes/decl.zig").Decl;
const Function = @import("../../nodes/decl.zig").Function;
const Builtin = @import("../../nodes/decl.zig").Builtin;
const Program = @import("../../nodes/program.zig").Program;
const Value = @import("../../nodes/value.zig").Value;
const VarAccess = @import("../../nodes/value.zig").VarAccess;
const UnaryOp = @import("../../nodes/value.zig").UnaryOp;
const BinaryOp = @import("../../nodes/value.zig").BinaryOp;
const FuncCall = @import("../../nodes/value.zig").FuncCall;
const Pointer = @import("../../nodes/value.zig").Pointer;
const Type = @import("../../nodes/type.zig").Type;

pub fn IrVisitor(comptime ArgTy: type, comptime RetTy: type) type {
    return struct {
        visitProgram: VisitProgramFn = defaultVisitProgram,
        visitDecl: VisitDeclFn = defaultVisitDecl,
        visitFunction: VisitFunctionFn = defaultVisitFunction,
        visitBBFunction: VisitBBFunctionFn = defaultVisitBBFunction,
        visitBuiltin: VisitBuiltinFn = defaultVisitBuiltin,
        visitBasicBlock: VisitBasicBlockFn = defaultVisitBasicBlock,

        visitStatement: VisitStatementFn = defaultVisitStatement,
        visitVarDecl: VisitVarDeclFn = defaultVisitVarDecl,
        visitBranch: VisitBranchFn = defaultVisitBranch,
        visitValueStmt: VisitValueStmtFn = defaultVisitValueStmt,
        visitRet: VisitRetFn = defaultVisitRet,

        visitValue: VisitValueFn = defaultVisitValue,
        visitUndef: VisitUndefFn = defaultVisitUndef,
        visitVarAccess: VisitVarAccessFn = defaultVisitVarAccess,
        visitInt: VisitIntFn = defaultVisitInt,
        visitFloat: VisitFloatFn = defaultVisitFloat,
        visitBool: VisitBoolFn = defaultVisitBool,
        visitUnaryOp: VisitUnaryOpFn = defaultVisitUnaryOp,
        visitBinaryOp: VisitBinaryOpFn = defaultVisitBinaryOp,
        visitFuncCall: VisitFuncCallFn = defaultVisitFuncCall,
        visitTypeVal: VisitTypeValFn = defaultVisitTypeVal,
        visitPtr: VisitPtrFn = defaultVisitPtr,

        const Self = @This();

        // Containers
        const VisitProgramFn = *const fn(self: Self, arg: ArgTy, program: *Program) RetTy;
        const VisitDeclFn = *const fn(self: Self, arg: ArgTy, decl: *Decl) RetTy;
        const VisitFunctionFn = *const fn(self: Self, arg: ArgTy, function: *Function(Stmt)) RetTy;
        const VisitBBFunctionFn = *const fn(self: Self, arg: ArgTy, bb_function: *Function(BasicBlock)) RetTy;
        const VisitBuiltinFn = *const fn(self: Self, arg: ArgTy, builtin: *Builtin) RetTy;
        const VisitBasicBlockFn = *const fn(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy;

        // Statements
        const VisitStatementFn = *const fn(self: Self, arg: ArgTy, stmt: *Stmt) RetTy;
        const VisitVarDeclFn = *const fn(self: Self, arg: ArgTy, decl: *VarDecl) RetTy;
        const VisitBranchFn = *const fn(self: Self, arg: ArgTy, branch: *Branch) RetTy;
        const VisitValueStmtFn = *const fn(self: Self, arg: ArgTy, val: *Value) RetTy;
        const VisitRetFn = *const fn(self: Self, arg: ArgTy, opt_val: *?Value) RetTy;

        // Values
        const VisitValueFn = *const fn(self: Self, arg: ArgTy, val: *Value) RetTy;
        const VisitUndefFn = *const fn(self: Self, arg: ArgTy) RetTy;
        const VisitVarAccessFn = *const fn(self: Self, arg: ArgTy, va: *VarAccess) RetTy;
        const VisitIntFn = *const fn(self: Self, arg: ArgTy, i: *i32) RetTy;
        const VisitFloatFn = *const fn(self: Self, arg: ArgTy, f: *f32) RetTy;
        const VisitBoolFn = *const fn(self: Self, arg: ArgTy, b: *u1) RetTy;
        const VisitUnaryOpFn = *const fn(self: Self, arg: ArgTy, uo: *UnaryOp) RetTy;
        const VisitBinaryOpFn = *const fn(self: Self, arg: ArgTy, bo: *BinaryOp) RetTy;
        const VisitFuncCallFn = *const fn(self: Self, arg: ArgTy, call: *FuncCall) RetTy;
        const VisitTypeValFn = *const fn(self: Self, arg: ArgTy, ty: *Type) RetTy;
        const VisitPtrFn = *const fn(self: Self, arg: ArgTy, ptr: *Pointer) RetTy;

        pub fn walkProgram(self: Self, arg: ArgTy, program: *Program) RetTy {
            for (program.decls) |*function| {
                try self.visitDecl(self, arg, function);
            }
        }

        pub fn walkDecl(self: Self, arg: ArgTy, decl: *Decl) RetTy {
            switch (decl.*) {
                .function => |*func| try self.visitFunction(self, arg, func),
                .bb_function => |*bb_func| try self.visitBBFunction(self, arg, bb_func),
                .builtin => |*b| try self.visitBuiltin(self, arg, b),
            }
        }

        pub fn walkFunction(self: Self, arg: ArgTy, function: *Function(Stmt)) RetTy {
            for (function.params) |*param| {
                try self.visitVarDecl(self, arg, param);
            }
            for (function.elements) |*stmt| {
                try self.visitStatement(self, arg, stmt);
            }
        }

        pub fn walkBBFunction(self: Self, arg: ArgTy, function: *Function(BasicBlock)) RetTy {
            for (function.params) |*param| {
                try self.visitVarDecl(self, arg, param);
            }
            for (function.elements) |*bb| {
                try self.visitBasicBlock(self, arg, bb);
            }
        }

        pub fn walkBuiltin(_: Self, _: ArgTy, _: *Builtin) RetTy {
            // Builtin parameters are constant, so they can't be walked
            // by this visitor.
        }

        pub fn walkBasicBlock(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy {
            for (bb.statements) |*stmt| {
                try self.visitStatement(self, arg, stmt);
            }
            if (bb.terminator) |*term| {
                try self.visitStatement(self, arg, term);
            }
        }

        pub fn walkStatement(self: Self, arg: ArgTy, stmt: *Stmt) RetTy {
            switch (stmt.*.stmt_kind) {
                .id => |*decl| try self.visitVarDecl(self, arg, decl),
                .branch => |*branch| try self.visitBranch(self, arg, branch),
                .value => |*value| try self.visitValueStmt(self, arg, value),
                .ret => |*opt_value| try self.visitRet(self, arg, opt_value),
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
            if (branch.expr) |*expr| {
                try self.visitValue(self, arg, expr);
            }
        }

        pub fn walkValue(self: Self, arg: ArgTy, val: *Value) RetTy {
            switch (val.*.val_kind) {
                .undef => try self.visitUndef(self, arg),
                .access => |*va| try self.visitVarAccess(self, arg, va),
                .int => |*i| try self.visitInt(self, arg, i),
                .float => |*f| try self.visitFloat(self, arg, f),
                .bool => |*b| try self.visitBool(self, arg, b),
                .unary => |*uo| try self.visitUnaryOp(self, arg, uo),
                .binary => |*bo| try self.visitBinaryOp(self, arg, bo),
                .call => |*call| try self.visitFuncCall(self, arg, call),
                .type_ => |*ty| try self.visitTypeVal(self, arg, ty),
                .ptr => |*ptr| try self.visitPtr(self, arg, ptr),
            }
        }

        pub fn walkUnaryOp(self: Self, arg: ArgTy, uo: *UnaryOp) RetTy {
            try self.visitValue(self, arg, uo.val);
        }

        pub fn walkBinaryOp(self: Self, arg: ArgTy, bo: *BinaryOp) RetTy {
            try self.visitValue(self, arg, bo.lhs);
            try self.visitValue(self, arg, bo.rhs);
        }

        pub fn walkFuncCall(self: Self, arg: ArgTy, call: *FuncCall) RetTy {
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

        pub fn defaultVisitBuiltin(self: Self, arg: ArgTy, builtin: *Builtin) RetTy {
            try self.walkBuiltin(arg, builtin);
        }

        pub fn defaultVisitBasicBlock(self: Self, arg: ArgTy, bb: *BasicBlock) RetTy {
            try self.walkBasicBlock(arg, bb);
        }

        pub fn defaultVisitStatement(self: Self, arg: ArgTy, stmt: *Stmt) RetTy {
            try self.walkStatement(arg, stmt);
        }

        pub fn defaultVisitUndef(_: Self, _: ArgTy) RetTy {
        }

        pub fn defaultVisitVarDecl(self: Self, arg: ArgTy, decl: *VarDecl) RetTy {
            try self.walkVarDecl(arg, decl);
        }

        pub fn defaultVisitValueStmt(self: Self, arg: ArgTy, val: *Value) RetTy {
            try self.walkValue(arg, val);
        }

        pub fn defaultVisitRet(self: Self, arg: ArgTy, opt_val: *?Value) RetTy {
            if (opt_val.*) |*val| {
                try self.walkValue(arg, val);
            }
        }

        pub fn defaultVisitInt(_: Self, _: ArgTy, _: *i32) RetTy {
        }

        pub fn defaultVisitFloat(_: Self, _: ArgTy, _: *f32) RetTy {
        }

        pub fn defaultVisitBool(_: Self, _: ArgTy, _: *u1) RetTy {
        }

        pub fn defaultVisitBranch(self: Self, arg: ArgTy, branch: *Branch) RetTy {
            try self.walkBranch(arg, branch);
        }

        pub fn defaultVisitValue(self: Self, arg: ArgTy, val: *Value) RetTy {
            try self.walkValue(arg, val);
        }

        pub fn defaultVisitVarAccess(_: Self, _: ArgTy, _: *VarAccess) RetTy {
        }

        pub fn defaultVisitUnaryOp(self: Self, arg: ArgTy, uo: *UnaryOp) RetTy {
            try self.walkUnaryOp(arg, uo);
        }

        pub fn defaultVisitBinaryOp(self: Self, arg: ArgTy, bo: *BinaryOp) RetTy {
            try self.walkBinaryOp(arg, bo);
        }

        pub fn defaultVisitFuncCall(self: Self, arg: ArgTy, call: *FuncCall) RetTy {
            try self.walkFuncCall(arg, call);
        }

        pub fn defaultVisitTypeVal(_: Self, _: ArgTy, _: *Type) RetTy {
        }

        pub fn defaultVisitPtr(_: Self, _: ArgTy, _: *Pointer) RetTy {
        }
    };
}
