const std = @import("std");
const fmt = std.fmt;
const AnyWriter = std.io.AnyWriter;

const Program = @import("../nodes/program.zig").Program;
const Stmt = @import("../nodes/statement.zig").Stmt;
const VarDecl = @import("../nodes/statement.zig").VarDecl;
const Value = @import("../nodes/value.zig").Value;
const UnaryOp = @import("../nodes/value.zig").UnaryOp;
const BinaryOp = @import("../nodes/value.zig").BinaryOp;
const Pointer = @import("../nodes/value.zig").Pointer;
const Type = @import("../nodes/type.zig").Type;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const Decl = @import("../nodes/decl.zig").Decl;
const Function = @import("../nodes/decl.zig").Function;
const Builtin = @import("../nodes/decl.zig").Builtin;
const Precedence = @import("../precedence.zig").Precedence;

const DisassemblerError = AnyWriter.Error || fmt.format_float.FormatError;

pub const Disassembler = struct {
    writer: AnyWriter,
    program: Program,
    var indent: usize = 0;

    pub fn disassemble(self: Disassembler) DisassemblerError!void {
        for (self.program.decls) |decl| {
            try self.disassembleDecl(decl);
        }
    }

    pub fn disassembleDecl(self: Disassembler, decl: Decl) DisassemblerError!void {
        switch (decl) {
            .function => |func| try self.disassembleFunction(func),
            .bb_function => |func| try self.disassembleBBFunction(func),
            .builtin => |builtin| try self.disassembleBuiltin(builtin),
        }
    }

    pub fn disassembleFunction(self: Disassembler, function: Function(Stmt)) DisassemblerError!void {
        try self.writer.print("func {s}(", .{function.name});
        try self.printParams(function.params);
        try self.writer.writeAll(") -> ");
        try self.disassembleType(function.ret_ty);
        try self.writer.writeAll(" {");
        indent += 1;
        for (function.elements) |stmt| {
            try self.disassembleStmt(stmt);
        }
        indent -= 1;
        try self.newline();
        try self.writer.writeAll("}");
        try self.newline();
    }

    pub fn disassembleBBFunction(
        self: Disassembler,
        function: Function(BasicBlock),
    ) DisassemblerError!void {
        try self.writer.print("func {s}(", .{function.name});
        try self.printParams(function.params);
        try self.writer.writeAll(") -> ");
        try self.disassembleType(function.ret_ty);
        try self.writer.writeAll(" {");
        indent += 1;
        for (function.elements) |bb| {
            try self.newline();
            if (bb.label) |label| {
                try self.writer.print("@{s} {{", .{label});
            } else {
                try self.writer.writeAll("{");
            }
            indent += 1;

            for (bb.statements) |stmt| {
                try self.disassembleStmt(stmt);
            }

            if (bb.terminator) |terminator| {
                try self.disassembleStmt(terminator);
            }

            indent -= 1;
            try self.newline();
            try self.writer.writeAll("}");
        }
        indent -= 1;
        try self.newline();
        try self.writer.writeAll("}");
        try self.newline();
    }

    pub fn disassembleBuiltin(self: Disassembler, builtin: Builtin) DisassemblerError!void {
        try self.writer.print("func {s}(", .{@tagName(builtin.kind)});
        try self.printParams(builtin.params);
        try self.writer.writeAll(") -> ");
        try self.disassembleType(builtin.ret_ty);
        try self.writer.writeAll(";");
        try self.newline();
    }

    pub fn disassembleStmt(self: Disassembler, stmt: Stmt) DisassemblerError!void {
        try self.newline();
        if (stmt.label) |label| {
            try self.writer.print("@{s}", .{label});
            try self.newline();
        }

        switch (stmt.stmt_kind) {
            .id => |decl| {
                try self.writer.print("let {s}", .{decl.name});
                if (decl.ty) |ty| {
                    try self.writer.writeAll(": ");
                    try self.disassembleType(ty);
                }
                if (decl.val) |value| {
                    try self.writer.writeAll(" = ");
                    try self.disassembleValue(value);
                }
            },
            .branch => |branch| {
                if (branch.expr) |expr| {
                    try self.writer.print("brc {s} ", .{branch.labelName()});
                    try self.disassembleValue(expr);
                } else {
                    try self.writer.print("br {s}", .{branch.labelName()});
                }
            },
            .ret => |opt_value| {
                try self.writer.writeAll("ret ");
                if (opt_value) |value| {
                    try self.disassembleValue(value);
                }
            },
            .value => |val| {
                try self.disassembleValue(val);
            },
        }

        try self.writer.writeAll(";");
    }

    pub fn disassembleValue(self: Disassembler, value: Value) DisassemblerError!void {
        switch (value.val_kind) {
            .undef => try self.writer.writeAll("undefined"),
            .access => |va| {
                if (va.name) |name| {
                    try self.writer.writeAll(name);
                } else if (va.offset) |offset| {
                    // This could be better
                    try self.writer.writeAll("@+");
                    try fmt.formatInt(offset, 10, .lower, .{}, self.writer);
                }
            },
            .int => |i| try fmt.formatInt(i, 10, .lower, .{}, self.writer),
            .float => |f| {
                var buf: [fmt.format_float.bufferSize(.decimal, f32)]u8 = undefined;
                const s = try fmt.format_float.formatFloat(&buf, f, .{});
                try fmt.formatBuf(s, .{}, self.writer);
            },
            .bool => |b| {
                if (b == 1) {
                    try self.writer.writeAll("true");
                } else {
                    try self.writer.writeAll("false");
                }
            },
            .unary => |unary| try self.disassembleUnary(unary),
            .binary => |binary| try self.disassembleBinary(binary),
            .call => |call| {
                try self.writer.writeAll(call.name());
                try self.writer.writeAll("(");
                var first = true;
                for (call.arguments) |arg| {
                    if (!first) {
                        try self.writer.writeAll(", ");
                    }

                    try self.disassembleValue(arg);
                    first = false;
                }

                try self.writer.writeAll(")");
            },
            .type_ => |ty| try self.disassembleType(ty),
            .ptr => |ptr| try self.disassemblePtr(ptr),
        }
    }

    pub fn disassembleUnary(self: Disassembler, unary: UnaryOp) DisassemblerError!void {
        const op = switch (unary.kind) {
            .not => "!",
            .deref => "*",
            .neg => "-",
        };

        try self.writer.writeAll(op);
        try self.disassembleValue(unary.val.*);
    }

    pub fn disassembleBinary(self: Disassembler, binary: BinaryOp) DisassemblerError!void {
        if (shouldPrintParens(binary.lhs, binary.kind)) {
            try self.writer.writeAll("(");
        }
        try self.disassembleValue(binary.lhs.*);
        if (shouldPrintParens(binary.lhs, binary.kind)) {
            try self.writer.writeAll(")");
        }
        const op = switch (binary.kind) {
            .assign => " = ",
            .eq => " == ",
            .add => " + ",
            .sub => " - ",
            .mul => " * ",
            .div => " / ",
            .and_ => " && ",
            .or_ => " || ",
            .lt => " < ",
            .le => " <= ",
            .gt => " > ",
            .ge => " >= ",
        };
        try self.writer.writeAll(op);
        if (shouldPrintParens(binary.rhs, binary.kind)) {
            try self.writer.writeAll("(");
        }
        try self.disassembleValue(binary.rhs.*);
        if (shouldPrintParens(binary.rhs, binary.kind)) {
            try self.writer.writeAll(")");
        }
    }

    /// Whether this should print parentheses around the child given this
    /// operator
    fn shouldPrintParens(child: *Value, op: BinaryOp.Kind) bool {
        return switch (child.*.val_kind) {
            .binary => |bo| !precedenceOf(bo.kind).gte(precedenceOf(op)),
            else => false,
        };
    }

    fn precedenceOf(op: BinaryOp.Kind) Precedence {
        return switch (op) {
            .assign => .assign,
            .eq => .equal,
            .add, .sub => .term,
            .mul, .div => .factor,
            .and_ => .and_,
            .or_ => .or_,
            .lt, .le, .gt, .ge => .compare,
        };
    }

    pub fn disassembleType(self: Disassembler, ty: Type) DisassemblerError!void {
        const name = switch (ty) {
            .int => "int",
            .float => "float",
            .boolean => "boolean",
            .type_ => "type",
            .pointer => "*",
            .none => "none",
            .runtime => "runtime",
            .err => "err",
        };
        try self.writer.writeAll(name);

        // Now print complex types
        switch (ty) {
            .pointer => |to| try self.disassembleType(to.*),
            else => {},
        }
    }

    pub fn disassemblePtr(self: Disassembler, ptr: Pointer) DisassemblerError!void {
        try self.writer.writeAll("@[");
        try self.disassembleType(ptr.ty);
        try self.writer.print("]{d}", .{ptr.to});
    }

    fn printParams(self: Disassembler, params: []const VarDecl) !void {
        var first = true;
        for (params) |param| {
            if (!first) {
                try self.writer.writeAll(", ");
            }
            // Type will probably be required from parsing but it may get here
            // without the type so don't crash.
            if (param.ty) |ty| {
                try self.disassembleType(ty);
                try self.writer.writeAll(" ");
            }

            try self.writer.print("{s}", .{param.name});

            first = false;
        }
    }

    fn newline(self: Disassembler) !void {
        try self.writer.writeAll("\n");
        var i: usize = 0;
        while (i < indent) : (i += 1) {
            try self.writer.writeAll("  ");
        }
    }
};
