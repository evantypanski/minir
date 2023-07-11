const std = @import("std");
const fmt = std.fmt;
const Writer = @import("std").fs.File.Writer;

const Program = @import("nodes/program.zig").Program;
const Stmt = @import("nodes/statement.zig").Stmt;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Value = @import("nodes/value.zig").Value;
const Type = @import("nodes/type.zig").Type;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;

const Disassembler = @This();

writer: Writer,
program: Program,
var indent: usize = 0;

pub fn disassemble(self: Disassembler) Writer.Error!void {
    for (self.program.decls) |decl| {
        try self.disassembleDecl(decl);
    }
}

pub fn disassembleDecl(self: Disassembler, decl: Decl) Writer.Error!void {
    switch (decl) {
        .function => |func| try self.disassembleFunction(func),
        .bb_function => |func| try self.disassembleBBFunction(func),
    }
}

pub fn disassembleFunction(
    self: Disassembler,
    function: Function(Stmt)
) Writer.Error!void {
    try self.writer.print("func {s}(", .{function.name});
    try self.printParams(function.params);
    try self.writer.writeAll(") -> ");
    try self.disassembleType(function.ret_ty);
    try self.writer.writeAll(" {");
    indent += 1;
    try self.newline();
    for (function.elements) |stmt| {
        try self.disassembleStmt(stmt);
        try self.newline();
    }
    indent -= 1;
    try self.newline();
    try self.writer.writeAll("}");
    try self.newline();
}

pub fn disassembleBBFunction(
    self: Disassembler,
    function: Function(BasicBlock),
) Writer.Error!void {
    try self.writer.print("func {s}(", .{function.name});
    try self.printParams(function.params);
    try self.writer.writeAll(") -> ");
    try self.disassembleType(function.ret_ty);
    try self.writer.writeAll(" {");
    indent += 1;
    try self.newline();
    for (function.elements) |bb| {
        if (bb.label) |label| {
            try self.writer.print("@{s} {{", .{label});
        } else {
            try self.writer.writeAll("{");
        }
        indent += 1;
        try self.newline();

        for (bb.statements) |stmt| {
            try self.disassembleStmt(stmt);
            try self.newline();
        }

        if (bb.terminator) |terminator| {
            try self.disassembleStmt(terminator);
        }

        indent -= 1;
        try self.newline();
        try self.writer.writeAll("}");
        try self.newline();
    }
    indent -= 1;
    try self.newline();
    try self.writer.writeAll("}");
    try self.newline();
}

pub fn disassembleStmt(self: Disassembler, stmt: Stmt) Writer.Error!void {
    if (stmt.label) |label| {
        try self.writer.print("@{s}", .{label});
        try self.newline();
    }

    switch (stmt.stmt_kind) {
        .debug => |val| {
            try self.writer.writeAll("debug(");
            try self.disassembleValue(val);
            try self.writer.writeAll(")");
        },
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
            switch (branch) {
                .jump =>
                    try self.writer.print("br {s}", .{branch.labelName()}),
                .conditional => |conditional| {
                    const instr_name = switch (conditional.kind) {
                        .zero => "brz",
                        .eq => "bre",
                        .less => "brl",
                        .less_eq => "brle",
                        .greater => "brg",
                        .greater_eq => "brge",
                    };
                    try self.writer.print(
                        "{s} {s} ",
                        .{instr_name, branch.labelName()}
                    );
                    try self.disassembleValue(conditional.lhs);
                    if (conditional.rhs) |value| {
                        try self.writer.writeAll(" ");
                        try self.disassembleValue(value);
                    }
                }
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
        }
    }
}

pub fn disassembleValue(self: Disassembler, value: Value) Writer.Error!void {
    switch (value) {
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
        .float => |f| try fmt.formatFloatDecimal(f, .{}, self.writer),
        .bool => |b| {
            if (b == 1) {
                try self.writer.writeAll("true");
            } else {
                try self.writer.writeAll("false");
            }
        },
        .binary => |binary| try self.disassembleBinary(binary),
        .call => |call| {
            try self.writer.writeAll(call.function);
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
    }
}

pub fn disassembleBinary(self: Disassembler, binary: Value.BinaryOp)
            Writer.Error!void {
    // TODO: Only print parens if necessary?
    try self.writer.writeAll("(");
    try self.disassembleValue(binary.lhs.*);
    const op = switch (binary.kind) {
        .assign => " = ",
        .add => " + ",
        .sub => " - ",
        .mul => " * ",
        .div => " / ",
        .fadd => " + ",
        .fsub => " - ",
        .fmul => " * ",
        .fdiv => " / ",
        .@"and" => " && ",
        .@"or" => " || ",
        .lt => " < ",
        .le => " <= ",
        .gt => " > ",
        .ge => " >= ",
    };
    try self.writer.writeAll(op);
    try self.disassembleValue(binary.rhs.*);
    try self.writer.writeAll(")");
}

pub fn disassembleType(self: Disassembler, ty: Type) Writer.Error!void {
    const name = switch (ty) {
        .int => "int",
        .float => "float",
        .boolean => "boolean",
        .none => "none",
    };
    try self.writer.writeAll(name);
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
