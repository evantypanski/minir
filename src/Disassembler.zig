const ir = @import("ir.zig");
const Writer = @import("std").fs.File.Writer;
const fmt = @import("std").fmt;

const Disassembler = @This();

writer: Writer,
function: ir.Function,
var indent: usize = 0;

pub fn disassemble(self: Disassembler) Writer.Error!void {
    try self.writer.print("fn @{s} {{", .{self.function.name});
    indent += 1;
    try self.newline();
    for (self.function.bbs.items) |bb| {
        if (bb.label) |label| {
            try self.writer.print("{s}: {{", .{label});
        } else {
            try self.writer.writeAll("{");
        }
        indent += 1;
        try self.newline();

        for (bb.instructions.items) |instr| {
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

pub fn disassembleInstr(self: Disassembler, instr: ir.Instr) Writer.Error!void {
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
                .unconditional =>
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
        .ret => try self.writer.writeAll("ret"),
    }
}

pub fn disassembleValue(self: Disassembler, value: ir.Value) Writer.Error!void {
    switch (value) {
        .undef => try self.writer.writeAll("undefined"),
        .access => |name| try self.writer.writeAll(name),
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
    }
}

pub fn disassembleBinary(self: Disassembler, binary: ir.Value.BinaryOp)
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

fn newline(self: Disassembler) !void {
    try self.writer.writeAll("\n");
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try self.writer.writeAll("  ");
    }
}
