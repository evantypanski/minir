const std = @import("std");

const IrError = error{
    NotAnInt,
    NotAFloat,
    NotABool,
    ExpectedTerminator,
    UnexpectedTerminator,
};

const ValueKind = enum {
    undef,
    access,
    int,
    float,
    bool,
    binary,
};

pub const Value = union(ValueKind) {
    pub const BinaryOp = struct {
        pub const Kind = enum {
            assign,

            add,
            sub,
            mul,
            div,

            // Float operators
            fadd,
            fsub,
            fmul,
            fdiv,

            @"and",
            @"or",

            lt,
            le,
            gt,
            ge,
        };

        kind: Kind,

        lhs: *Value,
        rhs: *Value,
    };

    undef,
    access: []const u8,
    int: i32,
    float: f32,
    bool: u1,
    binary: BinaryOp,

    pub fn initUndef() Value {
        return .undef;
    }

    pub fn initAccess(name: []const u8) Value {
        return .{ .access = name };
    }

    pub fn initInt(val: i32) Value {
        return .{
            .int = val,
        };
    }

    pub fn initFloat(f: f32) Value {
        return .{
            .float = f,
        };
    }

    pub fn initBool(val: bool) Value {
        return .{
            .bool = @boolToInt(val),
        };
    }

    pub fn initBinary(kind: BinaryOp.Kind, lhs: *Value, rhs: *Value) Value {
        return .{ .binary = .{
            .kind = kind,
            .lhs = lhs,
            .rhs = rhs,
        } };
    }

    // Turns a boolean Value into a native boolean. Should not be called
    // on non-bool Values.
    pub fn asBool(self: Value) IrError!bool {
        switch (self) {
            .bool => |val| return val == 1,
            else => return error.NotABool,
        }
    }

    // Turns an int Value into a native int, else it's not a boolean
    // returns 0.
    pub fn asInt(self: Value) IrError!i32 {
        switch (self) {
            .int => |val| return val,
            else => return error.NotAnInt,
        }
    }

    // Turns an int Value into a native int, else it's not a boolean
    // returns 0.
    pub fn asFloat(self: Value) IrError!f32 {
        switch (self) {
            .float => |val| return val,
            else => return error.NotAFloat,
        }
    }
};

const InstrKind = enum {
    debug,
    id,
    branch,
    ret,
};

pub const VarDecl = struct {
    name: []const u8,
    // Initial decl
    val: ?Value,
};

pub const Branch = struct {
    pub const Kind = enum {
        unconditional,
    };

    kind: Kind,
    success: []const u8,

    pub fn initUnconditional(to: []const u8) Branch {
        return .{
            .kind = .unconditional,
            .success = to,
        };
    }
};

pub const Instr = union(InstrKind) {
    debug: Value,
    id: VarDecl,
    branch: Branch,
    ret,

    pub fn isTerminator(self: Instr) bool {
        switch (self) {
            .debug, .id => return false,
            .branch, .ret => return true,
        }
    }
};

pub const BasicBlock = struct {
    instructions: std.ArrayList(Instr),
    terminator: ?Instr,
    label: ?[]const u8,
};

pub const Program = struct {
    instructions: std.ArrayList(Instr),
};

pub const BasicBlockBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    instructions: std.ArrayList(Instr),
    terminator: ?Instr,
    label: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .instructions = std.ArrayList(Instr).init(allocator),
            .terminator = null,
            .label = null,
        };
    }

    pub fn addInstruction(self: *Self, instr: Instr) !void {
        if (instr.isTerminator()) {
            return error.UnexpectedTerminator;
        }
        try self.instructions.append(instr);
    }

    pub fn setTerminator(self: *Self, term: Instr) !void {
        if (!term.isTerminator()) {
            return error.ExpectedTerminator;
        }

        self.terminator = term;
    }

    pub fn setLabel(self: *Self, label: []const u8) void {
        self.label = label;
    }

    pub fn build(self: Self) BasicBlock {
        return .{
            .instructions = self.instructions,
            .terminator = self.terminator,
            .label = self.label,
        };
    }
};

pub const Function = struct {
    const Self = @This();

    name: []const u8,
    bbs: std.ArrayList(BasicBlock),
    // Basic block name to index into bbs
    map: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, bbs: std.ArrayList(BasicBlock)) !Self {
        // Build the map
        var map = std.StringHashMap(usize).init(allocator);
        var i: usize = 0;
        while (i < bbs.items.len) : (i += 1) {
            const bb = bbs.items[i];
            if (bb.label) |label| {
                try map.put(label, i);
            }
        }

        return .{
            .name = name,
            .bbs = bbs,
            .map = map,
        };
    }
};

pub const FunctionBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    bbs: std.ArrayList(BasicBlock),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .bbs = std.ArrayList(BasicBlock).init(allocator),
        };
    }

    pub fn addBasicBlock(self: *Self, bb: BasicBlock) !void {
        try self.bbs.append(bb);
    }

    pub fn build(self: Self) !Function {
        return Function.init(self.allocator, self.name, self.bbs);
    }
};
