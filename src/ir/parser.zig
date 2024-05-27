const std = @import("std");

const Allocator = std.mem.Allocator;

const Program = @import("nodes/program.zig").Program;
const ProgramBuilder = @import("nodes/program.zig").ProgramBuilder;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Value = @import("nodes/value.zig").Value;
const BinaryOp = @import("nodes/value.zig").BinaryOp;
const UnaryOp = @import("nodes/value.zig").UnaryOp;
const Stmt = @import("nodes/statement.zig").Stmt;
const Branch = @import("nodes/statement.zig").Branch;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;
const FunctionBuilder = @import("nodes/decl.zig").FunctionBuilder;
const Type = @import("nodes/type.zig").Type;
const Loc = @import("sourceloc.zig").Loc;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Diagnostics = @import("diagnostics_engine.zig").Diagnostics;
const Precedence = @import("precedence.zig").Precedence;
const NodeError = @import("nodes/errors.zig").NodeError;

pub const Parser = struct {
    pub const Error = error {
        Unexpected,
        ExpectedNumber,
        Expected,
        NotANumber,
        NotABoolean,
        KeywordInvalidIdentifier,
        TooManyErrors,
    } || Lexer.Error || NodeError || Allocator.Error;
    const Self = @This();

    const Rule = struct {
        prefix: ?*const fn (self: *Self) Error!Value = null,
        infix: ?*const fn (self: *Self, other: Value) Error!Value = null,
        prec: Precedence = Precedence.none,
    };
    const RuleArray = [@typeInfo(Token.Tag).Enum.fields.len] Rule;

    allocator: Allocator,
    lexer: Lexer,
    current: Token,
    previous: Token,
    diag: Diagnostics,
    num_errors: usize,

    rules: RuleArray,

    pub fn init(
        allocator: Allocator,
        lexer: Lexer,
        diag_engine: Diagnostics
    ) Self {
        return .{
            .allocator = allocator,
            .lexer = lexer,
            .current = Token.init(.err, 0, 0),
            .previous = Token.init(.err, 0, 0),
            .diag = diag_engine,
            .num_errors = 0,
            .rules = make_rules(),
        };
    }

    pub fn parse(self: *Self) !Program {
        // We expect to be at the beginning. So we must advance once.
        if (!self.current.isValid()) {
            self.advance();
        }

        var builder = ProgramBuilder.init(self.allocator);
        errdefer builder.deinit();
        // A program is just a bunch of decls.
        // Theoretically we could keep going but for now just abort if parsing
        // has an issue. This will help keep errors down because our recovery
        // would be very bad right now.
        while (self.current.tag != .eof) {
            try builder.addDecl(try self.parseDecl());
        }

        // TODO: Make this a command line argument and let us try to run partial programs?
        // This would also apply to typechecking and others which may continue.. maybe
        if (self.num_errors > 0) {
            self.diag.diagNumErrors(self.num_errors, "parsing");
            return error.TooManyErrors;
        }

        return builder.build();
    }

    fn advance(self: *Self) void {
        self.previous = self.current;
        // Lex until valid token
        while(true) {
            if (self.lexer.lex()) |tok| {
                self.current = tok;
                return;
            } else |_| {
                // Error is already diagnosed
            }
        }
    }

    fn consume(self: *Self, tag: Token.Tag) Error!void {
        if (self.current.tag == tag) {
            self.advance();
            return;
        }

        self.num_errors += 1;
        self.diag.err(error.Expected, .{ @tagName(tag) }, self.current.loc);
        return error.Expected;
    }

    fn consumeKw(self: *Self, kw: Token.Keyword) Error!void {
        if (self.current.kw) |tok_kw| {
            if (tok_kw == kw) {
                self.advance();
                return;
            }
        }

        self.num_errors += 1;
        self.diag.err(error.Expected, .{ @tagName(kw) }, self.current.loc);
        return error.Expected;
    }

    fn parseDecl(self: *Self) Error!Decl {
        return Decl { .function = try self.parseFnDecl() };
    }

    fn parseFnDecl(self: *Self) Error!Function(Stmt) {
        try self.consumeKw(.func);
        try self.consume(.identifier);
        var builder = FunctionBuilder(Stmt)
            .init(self.allocator, self.lexer.getTokString(self.previous));
        errdefer builder.deinit();
        try self.consume(.lparen);
        while (self.match(.identifier)) {
            const name = self.lexer.getTokString(self.previous);
            const opt_ty = if (!self.match(.colon)) blk: {
                self.diag.err(error.Expected, .{ @tagName(.colon) }, self.current.loc);
                break :blk null;
            } else
                try self.maybeParseType();

            const param = VarDecl {
                .name = name,
                .val = null,
                .ty = opt_ty,
            };
            try builder.addParam(param);

            if (!self.match(.comma)) {
                break;
            }
        }
        try self.consume(.rparen);
        // Return
        try self.consume(.arrow);
        const ty = try self.maybeParseType() orelse .none;

        builder.setReturnType(ty);

        try self.consume(.lbrace);

        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            // Ignore errors here for now. In the future going until another statement starts
            // would be smart. If we were going to diagnose, we already did when we had all
            // necessary info
            const stmt = self.parseStmt() catch {
                self.advance();
                continue;
            };
            try builder.addElement(stmt);
        }

        // If we get here without right brace it's EOF
        try self.consume(.rbrace);

        const decl = try builder.build();
        return decl;
    }

    fn parseStmt(self: *Self) Error!Stmt {
        // Possibly match a semicolon in order to optionally delineate
        // statements
        defer _ = self.match(.semi);
        const label = if (self.match(.at))
                try self.parseLabel()
            else
                null;
        if (self.matchKw(.let)) {
            return self.parseLet(label);
        } else if (self.matchKw(.ret)) {
            return self.parseRet(label);
        } else if (self.current.isBranch()) {
            return self.parseBranch(label);
        } else {
            return self.parseExprStmt(label);
        }
    }

    fn parseLabel(self: *Self) Error![]const u8 {
        try self.consume(.identifier);
        return self.lexer.getTokString(self.previous);
    }

    fn parseLet(self: *Self, label: ?[]const u8) Error!Stmt {
        const start = self.previous.loc.start;
        try self.consume(.identifier);

        if (self.previous.kw) |_| {
            self.num_errors += 1;
            const snipped = self.diag.source_mgr.snip(self.previous.loc.start, self.previous.loc.end);
            self.diag.err(error.KeywordInvalidIdentifier, .{ snipped }, self.previous.loc);
            return error.KeywordInvalidIdentifier;
        }
        const var_name = self.lexer.getTokString(self.previous);
        // The type will be set if explicit or null if not. Note that
        // it's not .none if not set.
        const ty = if (self.match(.colon))
            try self.maybeParseType() orelse .none
        else
            null;
        const val = if (self.match(.eq)) try self.parseExpr() else null;
        return Stmt.init(
            .{
                .id = .{
                    .name = var_name,
                    .val = val,
                    .ty = ty,
                }
            },
            label,
            Loc.init(start, self.previous.loc.end),
        );
    }

    fn parseRet(self: *Self, label: ?[]const u8) Error!Stmt {
        const start = self.previous.loc.start;
        // Return is apparently always at the end of a block, I guess. That
        // will probably change.
        const val = if (self.current.tag == .rbrace)
            null
        else
            try self.parseExpr();

        return Stmt.init(
            .{ .ret = val },
            label,
            Loc.init(start, self.previous.loc.end),
        );
    }

    fn parseBranch(self: *Self, label: ?[]const u8) Error!Stmt {
        std.debug.assert(self.current.kw != null);
        const start = self.current.loc.start;
        const branch_kw = self.current.kw.?;
        self.advance();
        try self.consume(.identifier);
        const to = self.lexer.getTokString(self.previous);
        if (branch_kw == .br) {
            // Unconditional jump
            return Stmt.init(
                .{ .branch = Branch.initJump(to) },
                label,
                Loc.init(start, self.previous.loc.end),
            );
        } else if (branch_kw == .brc) {
            const if_true = try self.parseExpr();
            return Stmt.init(
                .{ .branch = Branch.initConditional(to, if_true) },
                label,
                Loc.init(start, self.previous.loc.end),
            );
        }

        const loc = self.previous.loc;
        // This shouldn't actually happen, should be able to gather than at
        // comptime eventually?
        self.num_errors += 1;
        self.diag.err(
            error.NotABranch,
            .{ self.diag.source_mgr.snip(loc.start, loc.end) },
            loc
        );
        return error.NotABranch;
    }

    fn parseExprStmt(self: *Self, label: ?[]const u8) Error!Stmt {
        const start = self.current.loc.start;
        return Stmt.init(
            .{ .value = try self.parseExpr() },
            label,
            Loc.init(start, self.previous.loc.end),
        );
    }

    fn parseExpr(self: *Self) Error!Value {
        return try self.parsePrecedence(.assign);
    }

    fn parseGrouping(self: *Self) Error!Value {
        // lparen
        self.advance();
        var val = try self.parsePrecedence(.assign);
        try self.consume(.rparen);
        // Annoying workaround: At this point the lparen is in the loc but the
        // rparen is not. In order to fix that we can just modify the loc. :(
        val.loc.end = self.previous.loc.end;
        return val;
    }

    fn getRule(self: Self, tok: Token) Rule {
        return self.rules[@intFromEnum(tok.tag)];
    }

    fn parsePrecedence(self: *Self, prec: Precedence) Error!Value {
        var lhs = if (self.getRule(self.current).prefix) |func|
            try func(self)
        else {
            self.num_errors += 1;
            return error.Unexpected;
        };

        while (self.precedenceOf(self.current.tag).gte(prec)) {
            lhs = if (self.getRule(self.current).infix) |func|
                try func(self, lhs)
            else {
                self.num_errors += 1;
                return error.Unexpected;
            };
        }

        return lhs;
    }

    // Parses an identifier as a value
    fn parseIdentifier(self: *Self) Error!Value {
        // Some keywords have special handling
        if (self.current.kw) |kw| {
            const start = self.previous.loc.start;
            switch (kw) {
                .true_, .false_ => return self.parseBoolean(),
                .undefined_ => {
                    self.advance();
                    return Value.initUndef(Loc.init(start, self.previous.loc.end));
                },
                else => {
                    // Anything else we'll just try to parse as a type
                    if (try self.maybeParseTypeValue()) |ty_val| {
                        return ty_val;
                    }
                    // Intentionally fallthrough
                }
            }
        }
        try self.consume(.identifier);
        const name = self.lexer.getTokString(self.previous);
        const start = self.previous.loc.start;
        const loc = Loc.init(start, self.previous.loc.end);
        return Value.initAccessName(name, loc);
    }

    // Parses a function call, where the identifier is the previous token.
    fn parseCall(self: *Self, other: Value) Error!Value {
        const start = self.previous.loc.start;
        try self.consume(.lparen);
        var arguments = std.ArrayList(Value).init(self.allocator);
        errdefer arguments.clearAndFree();
        if (self.current.tag != .rparen) {
            while (!self.lexer.isAtEnd()) {
                const arg = try self.parseExpr();
                try arguments.append(arg);
                if (!self.match(.comma)) {
                    break;
                }
            }
        }
        try self.consume(.rparen);
        const arg_slice = try arguments.toOwnedSlice();
        const loc = Loc.init(start, self.previous.loc.end);
        const fn_ptr = try self.allocator.create(Value);
        fn_ptr.* = other;
        return Value.initCall(fn_ptr, arg_slice, loc);
    }

    // Parses a unary op
    fn parseUnary(self: *Self) Error!Value {
        const start = self.previous.loc.start;
        const op_kind = try UnaryOp.Kind.fromTag(self.current.tag);
        self.advance();
        const val = try self.parsePrecedence(.unary);
        const val_ptr = try self.allocator.create(Value);
        val_ptr.* = val;

        const loc = Loc.init(start, self.previous.loc.end);
        return Value.initUnary(op_kind, val_ptr, loc);
    }

    fn parseBoolean(self: *Self) Error!Value {
        const start = self.previous.loc.start;
        const loc = Loc.init(start, self.previous.loc.end);
        return if (self.matchKw(.true_))
            Value.initBool(true, loc)
        else if (self.matchKw(.false_))
            Value.initBool(false, loc)
        else
            error.NotABoolean;
    }

    fn parseNumber(self: *Self) Error!Value {
        try self.consume(.num);
        const start = self.previous.loc.start;
        const loc = Loc.init(start, self.previous.loc.end);
        const num_str = self.lexer.getTokString(self.previous);
        var is_float = false;
        for (num_str) |char| {
            if (char == '.') {
                is_float = true;
                break;
            }
        }
        if (is_float) {
            if (std.fmt.parseFloat(f32, num_str)) |num| {
                return Value.initFloat(num, loc);
            } else |_| {
                self.num_errors += 1;
                self.diag.err(
                    error.NotANumber,
                    .{ self.diag.source_mgr.snip(loc.start, loc.end) },
                    loc
                );
                return error.NotANumber;
            }

        } else {
            if (std.fmt.parseInt(i32, num_str, 10)) |num| {
                return Value.initInt(num, loc);
            } else |_| {
                self.num_errors += 1;
                self.diag.err(
                    error.NotANumber,
                    .{ self.diag.source_mgr.snip(loc.start, loc.end) },
                    loc
                );
                return error.NotANumber;
            }
        }
    }

    fn parseBinary(self: *Self, other: Value) Error!Value {
        const prec = self.precedenceOf(self.current.tag);
        const op_kind = try BinaryOp.Kind.fromTag(self.current.tag);
        self.advance();
        const rhs = try self.parsePrecedence(prec.inc());
        const lhs_ptr = try self.allocator.create(Value);
        lhs_ptr.* = other;
        errdefer self.allocator.destroy(lhs_ptr);
        const rhs_ptr = try self.allocator.create(Value);

        rhs_ptr.* = rhs;

        return Value.initBinary(op_kind, lhs_ptr, rhs_ptr, other.loc.combine(rhs.loc));
    }

    fn maybeParseTypeValue(self: *Self) Error!?Value {
        const start = self.previous.loc.start;
        const opt_ty = try self.maybeParseType();
        return if (opt_ty) |ty|
            Value.initType(ty, Loc.init(start, self.previous.loc.end))
        else
            null;
    }

    // Parses a type name
    fn maybeParseType(self: *Self) Error!?Type {
        if (self.match(.star)) {
            const ty = if (try self.maybeParseType()) |ty|
                ty
            else {
                // If we're already trying to parse the type and hit the star, then we should
                // know that this will be a type
                self.num_errors += 1;
                const snipped = self.diag.source_mgr.snip(self.current.loc.start, self.current.loc.end);
                self.diag.err(error.InvalidTypeName, .{ snipped }, self.current.loc);
                return error.InvalidTypeName;
            };
            return try Type.initPtrAlloc(ty, self.allocator);
        }
        if (self.current.kw == null) {
            return null;
        }
        const ret: Type = switch (self.current.kw.?) {
            .int => .int,
            .float => .float,
            .boolean => .boolean,
            .none => .none,
            else => {
                return null;
            },
        };

        self.advance();
        return ret;
    }

    fn precedenceOf(self: Self, tag: Token.Tag) Precedence {
        return self.rules[@intFromEnum(tag)].prec;
    }

    fn match(self: *Self, tag: Token.Tag) bool {
        if (self.current.tag != tag) {
            return false;
        }

        self.advance();
        return true;
    }

    fn matchKw(self: *Self, kw: Token.Keyword) bool {
        if (self.current.kw) |tok_kw| {
            if (tok_kw == kw) {
                self.advance();
                return true;
            }
        }

        return false;
    }

    fn make_rules() RuleArray {
        var rules = std.mem.zeroes(RuleArray);
        rules[@intFromEnum(Token.Tag.lparen)] = .{
            .prefix = parseGrouping,
            .infix = parseCall,
            .prec = Precedence.call
        };
        rules[@intFromEnum(Token.Tag.identifier)] = .{
            .prefix = parseIdentifier,
            .infix = null,
            .prec = Precedence.none
        };
        rules[@intFromEnum(Token.Tag.num)] = .{
            .prefix = parseNumber,
            .infix = null,
            .prec = Precedence.none
        };
        rules[@intFromEnum(Token.Tag.bang)] = .{
            .prefix = parseUnary,
            .infix = parseBinary,
            .prec = Precedence.unary
        };
        rules[@intFromEnum(Token.Tag.eq)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.assign
        };
        rules[@intFromEnum(Token.Tag.pipe_pipe)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.or_
        };
        rules[@intFromEnum(Token.Tag.amp_amp)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.and_
        };
        rules[@intFromEnum(Token.Tag.eq_eq)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.equal
        };
        rules[@intFromEnum(Token.Tag.less)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.compare
        };
        rules[@intFromEnum(Token.Tag.less_eq)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.compare
        };
        rules[@intFromEnum(Token.Tag.greater)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.compare
        };
        rules[@intFromEnum(Token.Tag.greater_eq)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.compare
        };
        rules[@intFromEnum(Token.Tag.plus)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.term
        };
        rules[@intFromEnum(Token.Tag.minus)] = .{
            .prefix = parseUnary,
            .infix = parseBinary,
            .prec = Precedence.term
        };
        rules[@intFromEnum(Token.Tag.star)] = .{
            .prefix = parseUnary,
            .infix = parseBinary,
            .prec = Precedence.factor
        };
        rules[@intFromEnum(Token.Tag.slash)] = .{
            .prefix = null,
            .infix = parseBinary,
            .prec = Precedence.factor
        };
        return rules;
    }
};
