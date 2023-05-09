const std = @import("std");

const IrError = error{
    NotAnInt,
    NotAFloat,
    NotABool,
    ExpectedTerminator,
    UnexpectedTerminator,
    DuplicateMain,
    NoMainFunction,
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
    pub const VarAccess = struct {
        name: ?[]const u8,
        offset: ?usize,
    };

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
    access: VarAccess,
    int: i32,
    float: f32,
    bool: u1,
    binary: BinaryOp,

    pub fn initUndef() Value {
        return .undef;
    }

    pub fn initAccessName(name: []const u8) Value {
        return .{ .access = .{ .name = name, .offset = null } };
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
    call,
    branch,
    ret,
};

pub const VarDecl = struct {
    name: []const u8,
    // Initial decl
    val: ?Value,
};

pub const FuncCall = struct {
    function: []const u8,
    // TODO: Arguments
};

pub const Jump = struct {
    dest_label: []const u8,
    // dest_index will be set from 0 to the actual value when building the
    // function.
    dest_index: usize,
};

// Should only be created through Branch init instructions so that fields are
// properly set.
pub const ConditionalBranch = struct {
    pub const Kind = enum {
        zero,
        eq,
        less,
        less_eq,
        greater,
        greater_eq,
    };

    kind: Kind,
    success: []const u8,
    lhs: Value,
    rhs: ?Value,

    // dest_index will be set from 0 to the actual value when building the
    // function.
    dest_index: usize,
};

pub const BranchKind = enum {
    jump,
    conditional,
};

pub const Branch = union(BranchKind) {
    // Unconditional is just the label it goes to
    jump: Jump,
    conditional: ConditionalBranch,

    pub fn initJump(to: []const u8) Branch {
        return .{
            .jump = .{ .dest_label = to, .dest_index = 0 },
        };
    }

    pub fn initIfZero(to: []const u8, value: Value) Branch {
        return .{
            .conditional = .{
                .kind = .zero,
                .success = to,
                .lhs = value,
                .rhs = null,
                .dest_index = 0,
            },
        };
    }

    pub fn initBinaryConditional(to: []const u8, kind: ConditionalBranch.Kind,
                                 lhs: Value, rhs: Value) Branch {
        return .{
            .conditional = .{
                .kind = kind,
                .success = to,
                .lhs = lhs,
                .rhs = rhs,
                .dest_index = 0,
            },
        };
    }

    pub fn labelName(self: Branch) []const u8 {
        switch (self) {
            .jump => |j| return j.dest_label,
            .conditional => |conditional| return conditional.success,
        }
    }

    pub fn labelIndex(self: Branch) usize {
        switch (self) {
            .jump => |j| return j.dest_index,
            .conditional => |conditional| return conditional.dest_index,
        }
    }

    pub fn setIndex(self: *Branch, index: usize) void {
        switch (self.*) {
            .jump => |*j| j.dest_index = index,
            .conditional => |*conditional| conditional.dest_index = index,
        }
    }

};

pub const Instr = union(InstrKind) {
    debug: Value,
    id: VarDecl,
    call: FuncCall,
    branch: Branch,
    ret,

    pub fn isTerminator(self: Instr) bool {
        switch (self) {
            .debug, .id => return false,
            .call, .branch, .ret => return true,
        }
    }
};

pub const BasicBlock = struct {
    instructions: std.ArrayList(Instr),
    terminator: ?Instr,
    label: ?[]const u8,
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

    pub fn init(name: []const u8, bbs: std.ArrayList(BasicBlock)) !Self {
        return .{
            .name = name,
            .bbs = bbs,
        };
    }
};

pub const FunctionBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    bbs: std.ArrayList(BasicBlock),
    label_map: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .bbs = std.ArrayList(BasicBlock).init(allocator),
            .label_map = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn addBasicBlock(self: *Self, bb: BasicBlock) !void {
        if (bb.label) |label| {
            try self.label_map.put(label, self.bbs.items.len);
        }
        try self.bbs.append(bb);
    }

    pub fn build(self: Self) !Function {
        // Use map to set indexes in basic blocks
        var i: usize = 0;
        while (i < self.bbs.items.len) : (i += 1) {
            var bb = self.bbs.items[i];
            if (bb.terminator) |*terminator| {
                switch (terminator.*) {
                    .branch => |*branch| {
                        const index = self.label_map.get(branch.labelName())
                                orelse return error.UnknownLabel;
                        branch.setIndex(index);
                    },
                    else => {},
                }
            }
        }

        return Function.init(self.name, self.bbs);
    }
};

pub const Program = struct {
    functions: []Function,
};

pub const ProgramBuilder = struct {
    const Self = @This();

    functions: std.ArrayList(Function),
    main_idx: ?usize,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .functions = std.ArrayList(Function).init(allocator),
            .main_idx = null,
        };
    }

    pub fn addFunction(self: *Self, func: Function) !void {
        const is_main = std.mem.eql(u8, func.name, "main");
        if (is_main) {
            if (self.main_idx != null) {
                return error.DuplicateMain;
            } else {
                self.main_idx = self.functions.items.len;
            }
        }

        try self.functions.append(func);
    }

    pub fn build(self: Self) !Program {
        if (self.main_idx == null) {
            return error.NoMainFunction;
        }
        return Program { .functions = self.functions.items };
    }
};
