const std = @import("std");

pub const IrError = error{
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
    call,
};

pub const Value = union(ValueKind) {
    pub const VarAccess = struct {
        name: ?[]const u8,
        offset: ?isize,
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

    pub const FuncCall = struct {
        function: []const u8,
        arguments: ?std.ArrayList(Value),
    };

    undef,
    access: VarAccess,
    int: i32,
    float: f32,
    bool: u1,
    binary: BinaryOp,
    call: FuncCall,

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

    pub fn initCall(function: []const u8, arguments: ?std.ArrayList(Value)) Value {
        return .{ .call = .{ .function = function, .arguments = arguments } };
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

pub const Type = enum {
    int,
    float,
    boolean,
    // void but avoiding name conflicts is good :)
    none,
};

const InstrKind = enum {
    debug,
    id,
    branch,
    ret,
    value,
};

pub const VarDecl = struct {
    name: []const u8,
    // Initial decl
    val: ?Value,
    ty: Type,
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
    branch: Branch,
    ret: ?Value,
    value: Value,

    pub fn isTerminator(self: Instr) bool {
        switch (self) {
            .debug, .id, .value => return false,
            .branch, .ret => return true,
        }
    }
};

pub const BasicBlock = struct {
    instructions: std.ArrayList(Instr),
    terminator: ?Instr,
    label: ?[]const u8,

    pub fn deinit(self: *BasicBlock) void {
        self.instructions.deinit();
    }
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
    params: std.ArrayList(VarDecl),
    ret_ty: Type,

    pub fn init(name: []const u8, bbs: std.ArrayList(BasicBlock),
                params: std.ArrayList(VarDecl), ret_ty: Type) !Self {
        return .{
            .name = name,
            .bbs = bbs,
            .params = params,
            .ret_ty = ret_ty,
        };
    }

    pub fn deinit(self: *Function) void {
        for (self.bbs.items) |*bb| {
            bb.deinit();
        }
        self.bbs.deinit();
        self.params.deinit();
    }
};

pub const FunctionBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    bbs: std.ArrayList(BasicBlock),
    params: std.ArrayList(VarDecl),
    label_map: std.StringHashMap(usize),
    ret_ty: ?Type,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .bbs = std.ArrayList(BasicBlock).init(allocator),
            .params = std.ArrayList(VarDecl).init(allocator),
            .label_map = std.StringHashMap(usize).init(allocator),
            .ret_ty = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.label_map.deinit();
    }

    pub fn addBasicBlock(self: *Self, bb: BasicBlock) !void {
        if (bb.label) |label| {
            try self.label_map.put(label, self.bbs.items.len);
        }
        try self.bbs.append(bb);
    }

    pub fn setReturnType(self: *Self, ty: Type) void {
        self.ret_ty = ty;
    }

    pub fn addParam(self: *Self, param_decl: VarDecl) !void {
        try self.params.append(param_decl);
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

        return Function.init(self.name, self.bbs, self.params,
                             self.ret_ty orelse .none);
    }
};

pub const Program = struct {
    functions: std.ArrayList(Function),

    pub fn deinit(self: *Program) void {
        for (self.functions.items) |*function| {
            function.deinit();
        }
        self.functions.deinit();
    }
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
        return Program { .functions = self.functions };
    }
};

test "deinit works" {
    var func_builder = FunctionBuilder.init(std.testing.allocator, "main");
    defer func_builder.deinit();

    var bb1_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb1_builder.setLabel("bb1");
    try bb1_builder.addInstruction(
        Instr {
            .id = .{
                .name = "hi",
                .val = .{ .int = 99 },
                .ty = .int,
            }
        }
    );
    var hi_access = Value.initAccessName("hi");
    try bb1_builder.addInstruction(Instr{ .debug = hi_access });
    try bb1_builder.addInstruction(.{ .debug = Value.initCall("f") });
    try func_builder.addBasicBlock(bb1_builder.build());

    const func = try func_builder.build();

    var bb4_builder = BasicBlockBuilder.init(std.testing.allocator);
    bb4_builder.setLabel("bb4");
    try bb4_builder.setTerminator(.{.ret = Value.initInt(5)});

    var func2_builder = FunctionBuilder.init(std.testing.allocator, "f");
    defer func2_builder.deinit();
    func2_builder.setReturnType(.int);
    try func2_builder.addBasicBlock(bb4_builder.build());
    const func2 = try func2_builder.build();

    var prog_builder = ProgramBuilder.init(std.testing.allocator);
    try prog_builder.addFunction(func);
    try prog_builder.addFunction(func2);

    var program = try prog_builder.build();
    program.deinit();
}
