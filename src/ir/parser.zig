const std = @import("std");

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
const ParseError = @import("errors.zig").ParseError;
const Type = @import("nodes/type.zig").Type;
const Loc = @import("sourceloc.zig").Loc;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Diagnostics = @import("diagnostics_engine.zig").Diagnostics;

pub const Parser = struct {
    const Self = @This();

    const Precedence = enum(u8) {
        none,
        assign,
        or_,
        and_,
        equal,
        compare,
        term,
        factor,
        unary,
        call,
        primary,

        pub fn gte(self: Precedence, other: Precedence) bool {
            return @intFromEnum(self) >= @intFromEnum(other);
        }

        pub fn inc(self: Precedence) Precedence {
            if (self == .primary) {
                return .primary;
            }

            return @enumFromInt(@intFromEnum(self) + 1);
        }
    };

    allocator: std.mem.Allocator,
    lexer: Lexer,
    current: Token,
    previous: Token,
    diag: Diagnostics,

    pub fn init(
        allocator: std.mem.Allocator,
        lexer: Lexer,
        diag_engine: Diagnostics
    ) Self {
        return .{
            .allocator = allocator,
            .lexer = lexer,
            .current = Token.init(.none, 0, 0),
            .previous = Token.init(.none, 0, 0),
            .diag = diag_engine
        };
    }

    pub fn parse(self: *Self) !Program {
        // We expect to be at the beginning. So we must advance once.
        if (!self.current.isValid()) {
            self.advance();
        }

        var builder = ProgramBuilder.init(self.allocator);
        // A program is just a bunch of decls.
        // Theoretically we could keep going but for now just abort if parsing
        // has an issue. This will help keep errors down because our recovery
        // would be very bad right now.
        while (self.current.tag != .eof) {
            try builder.addDecl(try self.parseDecl());
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

    fn consume(self: *Self, tag: Token.Tag) ParseError!void {
        if (self.current.tag == tag) {
            self.advance();
            return;
        }

        self.diag.err(error.Expected, .{ @tagName(tag) }, self.current.loc);
        return error.Expected;
    }

    fn parseDecl(self: *Self) ParseError!Decl {
        return Decl { .function = try self.parseFnDecl() };
    }

    fn parseFnDecl(self: *Self) ParseError!Function(Stmt) {
        try self.consume(.func);
        try self.consume(.identifier);
        var builder = FunctionBuilder(Stmt)
            .init(self.allocator, self.lexer.getTokString(self.previous));
        try self.consume(.lparen);
        while (self.match(.identifier)) {
            const name = self.lexer.getTokString(self.previous);
            const opt_ty = if (!self.match(.colon)) blk: {
                self.diag.err(error.Expected, .{ @tagName(.colon) }, self.current.loc);
                break :blk null;
            } else if (self.parseType()) |ty|
                ty
            else |_| blk: {
                break :blk null;
            };

            const param = VarDecl {
                .name = name,
                .val = null,
                .ty = opt_ty,
            };
            builder.addParam(param) catch return error.MemoryError;

            if (!self.match(.comma)) {
                break;
            }
        }
        try self.consume(.rparen);
        // Return
        try self.consume(.arrow);
        const ty = if (self.parseType()) |ty|
            ty
        else |_| blk: {
            break :blk .none;
        };

        builder.setReturnType(ty);

        try self.consume(.lbrace);

        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            if (builder.addElement(try self.parseStmt())) {}
            else |_| { return error.MemoryError; }
        }

        // If we get here without right brace it's EOF
        try self.consume(.rbrace);

        const decl = if (builder.build()) |decl|
                decl
            else |_|
                error.MemoryError;
        return decl;
    }

    fn parseStmt(self: *Self) ParseError!Stmt {
        // Possibly match a semicolon in order to optionally delineate
        // statements
        defer _ = self.match(.semi);
        const label = if (self.match(.at))
                try self.parseLabel()
            else
                null;
        if (self.match(.debug)) {
            // Debug looks like a call, but really it's just a statement
            // that we print the result of. That may change one day, since
            // alloc is implemented as a function call.
            return self.parseDebug(label);
        } else if (self.match(.let)) {
            return self.parseLet(label);
        } else if (self.match(.ret)) {
            return self.parseRet(label);
        } else if (self.current.tag.isBranch()) {
            return self.parseBranch(label);
        } else {
            return self.parseExprStmt(label);
        }
    }

    fn parseLabel(self: *Self) ParseError![]const u8 {
        try self.consume(.identifier);
        return self.lexer.getTokString(self.previous);
    }

    fn parseDebug(self: *Self, label: ?[]const u8) ParseError!Stmt {
        const start = self.previous.loc.start;
        try self.consume(.lparen);
        const val = try self.parseExpr();
        try self.consume(.rparen);
        return Stmt.init(
            .{ .debug = val },
            label,
            Loc.init(start, self.previous.loc.end),
        );
    }

    fn parseLet(self: *Self, label: ?[]const u8) ParseError!Stmt {
        const start = self.previous.loc.start;
        try self.consume(.identifier);
        const var_name = self.lexer.getTokString(self.previous);
        // The type will be set if explicit or null if not. Note that
        // it's not .none if not set.
        const ty = if (self.match(.colon)) blk: {
            if (self.parseType()) |ty|
                break :blk ty
            else |_| {
                break :blk .none;
            }
        } else null;
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

    fn parseRet(self: *Self, label: ?[]const u8) ParseError!Stmt {
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

    fn parseBranch(self: *Self, label: ?[]const u8) ParseError!Stmt {
        const start = self.previous.loc.start;
        const branch_tag = self.current.tag;
        self.advance();
        try self.consume(.identifier);
        const to = self.lexer.getTokString(self.previous);
        if (branch_tag == .br) {
            // Unconditional jump
            return Stmt.init(
                .{ .branch = Branch.initJump(to) },
                label,
                Loc.init(start, self.previous.loc.end),
            );
        } else if (branch_tag == .brc) {
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
        self.diag.err(
            error.NotABranch,
            .{ self.diag.source_mgr.snip(loc.start, loc.end) },
            loc
        );
        return error.NotABranch;
    }

    fn parseExprStmt(self: *Self, label: ?[]const u8) ParseError!Stmt {
        const start = self.current.loc.start;
        return Stmt.init(
            .{ .value = try self.parseExpr() },
            label,
            Loc.init(start, self.previous.loc.end),
        );
    }

    fn parseExpr(self: *Self) ParseError!Value {
        return try self.parsePrecedence(.assign);
    }

    fn parseGrouping(self: *Self) ParseError!Value {
        // lparen
        self.advance();
        var val = try self.parsePrecedence(.assign);
        try self.consume(.rparen);
        // Annoying workaround: At this point the lparen is in the loc but the
        // rparen is not. In order to fix that we can just modify the loc. :(
        val.loc.end = self.previous.loc.end;
        return val;
    }

    fn parsePrecedence(self: *Self, prec: Precedence) ParseError!Value {
        const start = self.previous.loc.start;
        // Prefixes. Literals, parenthesized expressions, and ids can start an
        // expression statement.
        // TODO add precedence here
        var lhs = if (self.current.tag == .lparen)
            try self.parseGrouping()
        else if (self.match(.identifier) or self.match(.alloc))
            if (self.current.tag == .lparen)
                try self.parseCall()
            else
                try self.parseIdentifier()
        else if (self.current.isUnaryOp())
            try self.parseUnary()
        else
            try self.parseLiteral();

        while (true) {
            const this_prec = bindingPower(self.current.tag);
            if (self.current.isBinaryOp() and this_prec.gte(prec)) {
                const op_kind =
                    try BinaryOp.Kind.fromTag(self.current.tag);
                self.advance();
                var rhs = try self.parsePrecedence(this_prec.inc());
                const lhs_ptr = if (self.allocator.create(Value)) |ptr|
                        ptr
                    else |_|
                        return error.MemoryError;
                lhs_ptr.* = lhs;
                const rhs_ptr = if (self.allocator.create(Value)) |ptr|
                        ptr
                    else |_|
                        return error.MemoryError;

                rhs_ptr.* = rhs;

                const loc = Loc.init(start, self.previous.loc.end);
                lhs = Value.initBinary(op_kind, lhs_ptr, rhs_ptr, loc);
            } else {
                return lhs;
            }
        }
    }

    // Parses an identifier as a value
    fn parseIdentifier(self: *Self) ParseError!Value {
        // We may get here with a keyword, so make sure the token is an
        // identifier since they are not valid identifiers.
        if (self.previous.tag != .identifier) {
            self.diag.err(
                error.KeywordInvalidIdentifier,
                .{
                    self.diag.source_mgr.snip(
                        self.previous.loc.start, self.previous.loc.end
                    )
                },
                self.previous.loc
            );
            return error.KeywordInvalidIdentifier;
        }
        // Already consumed identifier
        const name = self.lexer.getTokString(self.previous);
        const start = self.previous.loc.start;
        const loc = Loc.init(start, self.previous.loc.end);
        return Value.initAccessName(name, loc);
    }

    // Parses a function call, where the identifier is the previous token.
    fn parseCall(self: *Self) ParseError!Value {
        const start = self.previous.loc.start;
        const builtin = self.previous.tag != .identifier;
        // Already consumed identifier
        const name = self.lexer.getTokString(self.previous);
        try self.consume(.lparen);
        var arguments = std.ArrayList(Value).init(self.allocator);
        if (self.current.tag != .rparen) {
            while (!self.lexer.isAtEnd()) {
                const arg = try self.parseExpr();
                arguments.append(arg) catch return error.MemoryError;
                if (!self.match(.comma)) {
                    break;
                }
            }
        }
        try self.consume(.rparen);
        const arg_slice = arguments.toOwnedSlice()
            catch return error.MemoryError;
        const loc = Loc.init(start, self.previous.loc.end);
        return Value.initCall(name, builtin, arg_slice, loc);
    }

    // Parses a unary op
    fn parseUnary(self: *Self) ParseError!Value {
        const start = self.previous.loc.start;
        const op_kind = try UnaryOp.Kind.fromTag(self.current.tag);
        self.advance();
        const val = try self.parsePrecedence(.unary);
        const val_ptr = if (self.allocator.create(Value)) |ptr|
                ptr
            else |_|
                return error.MemoryError;
        val_ptr.* = val;

        const loc = Loc.init(start, self.previous.loc.end);
        return Value.initUnary(op_kind, val_ptr, loc);
    }

    fn parseLiteral(self: *Self) ParseError!Value {
        const start = self.previous.loc.start;
        return if (self.current.tag == .true_ or self.current.tag == .false_)
            try self.parseBoolean()
        else if (self.current.tag == .num)
            try self.parseNumber()
        else if (self.match(.undefined_))
            Value.initUndef(Loc.init(start, self.previous.loc.end))
        else if (self.parseType() catch null) |ty|
            Value.initType(ty, Loc.init(start, self.previous.loc.end))
        else
            error.NotALiteral;
    }

    fn parseBoolean(self: *Self) ParseError!Value {
        const start = self.previous.loc.start;
        const loc = Loc.init(start, self.previous.loc.end);
        return if (self.match(.true_))
            Value.initBool(true, loc)
        else if (self.match(.false_))
            Value.initBool(false, loc)
        else
            error.NotABoolean;
    }

    fn parseNumber(self: *Self) ParseError!Value {
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
                self.diag.err(
                    error.NotANumber,
                    .{ self.diag.source_mgr.snip(loc.start, loc.end) },
                    loc
                );
                return error.NotANumber;
            }
        }
    }

    // Parses a type name
    fn parseType(self: *Self) ParseError!Type {
        self.advance();
        return switch (self.previous.tag) {
            .int => .int,
            .float => .float,
            .boolean => .boolean,
            .none => .none,
            else => error.InvalidTypeName,
        };
    }

    fn bindingPower(tag: Token.Tag) Precedence {
        return switch (tag) {
            .bang => .unary,
            .eq => .assign,
            .pipe_pipe => .or_,
            .amp_amp => .and_,
            .eq_eq => .equal,
            .less, .less_eq, .greater, .greater_eq => .compare,
            .plus, .minus => .term,
            .star, .slash => .factor,
            else => .none,
        };
    }

    fn match(self: *Self, tag: Token.Tag) bool {
        if (self.current.tag != tag) {
            return false;
        }

        self.advance();
        return true;
    }
};
