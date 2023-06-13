const fmt = @import("std").fmt;
const Writer = @import("std").fs.File.Writer;

const Program = @import("nodes/program.zig").Program;
const Instr = @import("nodes/instruction.zig").Instr;
const VarDecl = @import("nodes/instruction.zig").VarDecl;
const Value = @import("nodes/value.zig").Value;
const Type = @import("nodes/type.zig").Type;

const Disassembler = @This();

writer: Writer,
program: Program,
var indent: usize = 0;

pub fn disassemble(self: Disassembler) Writer.Error!void {
    for (self.program.functions) |function| {
        try self.writer.print("func @{s}(", .{function.name});
        try self.printParams(function.params);
        try self.writer.writeAll(") -> ");
        try self.disassembleType(function.ret_ty);
        try self.writer.writeAll(" {");
        indent += 1;
        try self.newline();
        for (function.bbs) |bb| {
            if (bb.label) |label| {
                try self.writer.print("{s}: {{", .{label});
            } else {
                try self.writer.writeAll("{");
            }
            indent += 1;
            try self.newline();

            for (bb.instructions) |instr| {
                try self.disassembleInstr(instr);
                try self.newline();
            }

            if (bb.terminator) |terminator| {
                try self.disassembleInstr(terminator);
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
}

pub fn disassembleInstr(self: Disassembler, instr: Instr) Writer.Error!void {
    switch (instr) {
        .debug => |val| {
            try self.writer.writeAll("debug(");
            try self.disassembleValue(val);
            try self.writer.writeAll(")");
        },
        .id => |decl| {
            try self.writer.writeAll(decl.name);
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
}

pub fn disassembleType(self: Disassembler, ty: Type) Writer.Error!void {
    const name = switch (ty) {
        .int => "int",
        .float => "float",
        .boolean => "boolean",
        .none => "void",
    };
    try self.writer.writeAll(name);
}

fn printParams(self: Disassembler, params: []const VarDecl) !void {
    var first = true;
    for (params) |param| {
        if (!first) {
            try self.writer.writeAll(", ");
        }
        try self.disassembleType(param.ty);
        try self.writer.print(" {s}", .{param.name});

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
