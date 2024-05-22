const std = @import("std");

const Allocator = std.mem.Allocator;

const Function = @import("../nodes/decl.zig").Function;
const FunctionBuilder = @import("../nodes/decl.zig").FunctionBuilder;
const Decl = @import("../nodes/decl.zig").Decl;
const BasicBlock = @import("../nodes/basic_block.zig").BasicBlock;
const Stmt = @import("../nodes/statement.zig").Stmt;
const Branch = @import("../nodes/statement.zig").Branch;
const Value = @import("../nodes/value.zig").Value;
const IrVisitor = @import("visitor.zig").IrVisitor;
const Program = @import("../nodes/program.zig").Program;

const BranchesError = error{
    LabelNotFound,
} || Allocator.Error;

pub const ResolveBranchesPass = struct {
    const Self = @This();
    const VisitorTy = IrVisitor(*Self, BranchesError!void);

    allocator: Allocator,
    label_map: std.StringHashMap(usize),
    fn_element: usize,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .label_map = std.StringHashMap(usize).init(allocator),
            .fn_element = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.label_map.clearAndFree();
    }

    pub const FindBranchesVisitor = VisitorTy {
        .visitFunction = visitFunction,
        .visitBBFunction = visitBBFunction,
    };

    pub const PopulateBranchesVisitor = VisitorTy {
        .visitBranch = visitBranch,
    };

    pub fn execute(self: *Self, program: *Program) BranchesError!void {
        // Fill out the map
        try FindBranchesVisitor.visitProgram(FindBranchesVisitor, self, program);
    }

    pub fn visitFunction(
        visitor: VisitorTy,
        self: *Self,
        func: *Function(Stmt)
    ) BranchesError!void {
        _ = visitor;
        var ele: usize = 0;
        for (func.elements) |bb| {
            try self.addLabelIfPresent(bb, ele);
            ele += 1;
        }
        try PopulateBranchesVisitor.walkFunction(self, func);
        self.*.label_map.clearRetainingCapacity();
    }

    pub fn visitBBFunction(
        visitor: VisitorTy,
        self: *Self,
        func: *Function(BasicBlock)
    ) BranchesError!void {
        _ = visitor;
        var ele: usize = 0;
        for (func.elements) |bb| {
            try self.addLabelIfPresent(bb, ele);
            ele += 1;
        }
        try PopulateBranchesVisitor.walkBBFunction(self, func);
        self.*.label_map.clearRetainingCapacity();
    }

    fn addLabelIfPresent(self: *Self, labeled: anytype, ele: usize) BranchesError!void {
        if (labeled.getLabel()) |label| {
            try self.*.label_map.put(label, ele);
        }
    }

    pub fn visitBranch(
        visitor: VisitorTy,
        self: *Self,
        br: *Branch
    ) BranchesError!void {
        _ = visitor;
        br.*.dest_index = (self.*.label_map.get(br.*.dest_label) orelse return error.LabelNotFound);
    }
};
