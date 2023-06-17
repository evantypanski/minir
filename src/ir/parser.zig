const std = @import("std");

const Program = @import("nodes/program.zig").Program;
const ProgramBuilder = @import("nodes/program.zig").ProgramBuilder;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Value = @import("nodes/value.zig").Value;
const Instr = @import("nodes/instruction.zig").Instr;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;
const FunctionBuilder = @import("nodes/decl.zig").FunctionBuilder;
const ParseError = @import("errors.zig").ParseError;
const Type = @import("nodes/type.zig").Type;

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
            return @enumToInt(self) >= @enumToInt(other);
        }

        pub fn inc(self: Precedence) Precedence {
            if (self == .primary) {
                return .primary;
            }

            return @intToEnum(Precedence, @enumToInt(self) + 1);
        }
    };

    allocator: std.mem.Allocator,
    lexer: Lexer,
    current: Token,
    previous: Token,

    pub fn init(allocator: std.mem.Allocator, lexer: Lexer) Self {
        return .{
            .allocator = allocator,
            .lexer = lexer,
            .current = Token.init(.none, 0, 0),
            .previous = Token.init(.none, 0, 0),
        };
    }

    pub fn parse(self: *Self) !Program {
        // We expect to be at the beginning. So we must advance once.
        if (!self.current.isValid()) {
            self.advance();
        }

        var builder = ProgramBuilder.init(self.allocator);
        // A program is just a bunch of decls.
        while (self.current.tag != .eof) : (self.advance()) {
            if (self.parseDecl()) |decl| {
                try builder.addDecl(decl);
            } else |err| {
                self.diagCurrent(err);
            }
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
            } else |err| {
                self.diag(self.lexer.getLastString(), err);
            }
        }
    }

    fn consume(self: *Self, tag: Token.Tag, err: ParseError) ParseError!void {
        if (self.current.tag == tag) {
            self.advance();
            return;
        }

        //self.diagCurrent(error_message);
        return err;
    }

    fn parseDecl(self: *Self) ParseError!Decl {
        return Decl { .function = try self.parseFnDecl() };
    }

    fn parseFnDecl(self: *Self) ParseError!Function(Instr) {
        try self.consume(.func, error.ExpectedKeywordFunc);
        try self.consume(.at, error.ExpectedAt);
        try self.consume(.identifier, error.ExpectedIdentifier);
        var builder = FunctionBuilder(Instr)
            .init(self.allocator, self.lexer.getTokString(self.previous));
        try self.consume(.lparen, error.ExpectedLParen);
        // TODO: Arguments
        try self.consume(.rparen, error.ExpectedRParen);
        // Return
        try self.consume(.arrow, error.ExpectedArrow);
        try self.consume(.identifier, error.ExpectedIdentifier);
        const type_name = self.lexer.getTokString(self.previous);
        const ty = if (Type.from_string(type_name)) |ty|
                ty
            else |err| blk: {
                self.diagPrevious(err);
                break :blk .none;
            };
        builder.setReturnType(ty);

        try self.consume(.lbrace, error.ExpectedLBrace);

        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            if (builder.addElement(try self.parseStmt())) {}
            else |_| { return error.MemoryError; }
        }

        // If we get here without right brace it's EOF
        try self.consume(.rbrace, error.ExpectedRBrace);

        const decl = if (builder.build()) |decl|
                decl
            else |_|
                error.MemoryError;
        return decl;
    }

    fn parseStmt(self: *Self) ParseError!Instr {
        if (self.match(.debug)) {
            return self.parseDebug();
        } else if (self.match(.let)) {
            try self.consume(.identifier, error.ExpectedIdentifier);
            const var_name = self.lexer.getTokString(self.previous);
            const val = if (self.match(.eq)) try self.parseExpr() else null;
            return .{
                .id = .{
                    .name = var_name,
                    .val = val,
                    .ty = null,
                }
            };
        } else {
            return .{
                .value = try self.parseExpr(),
            };
        }
    }

    fn parseDebug(self: *Self) ParseError!Instr {
        try self.consume(.lparen, error.ExpectedLParen);
        const val = try self.parseExpr();
        try self.consume(.rparen, error.ExpectedRParen);
        return .{ .debug = val };
    }

    fn parseExpr(self: *Self) ParseError!Value {
        return try self.parsePrecedence(.assign);
    }

    fn parseGrouping(self: *Self) ParseError!Value {
        // lparen
        self.advance();
        const val = try self.parsePrecedence(.assign);
        try self.consume(.rparen, error.ExpectedRParen);
        return val;
    }

    fn parsePrecedence(self: *Self, prec: Precedence) ParseError!Value {
        // Prefixes. Literals, parenthesized expressions, and ids can start an
        // expression statement.
        // TODO: Unary ops
        var lhs = if (self.current.tag == .lparen)
            try self.parseGrouping()
        else if (self.current.tag == .identifier)
            try self.parseIdentifier()
        else
            try self.parseLiteral();

        while (true) {
            const this_prec = bindingPower(self.current.tag);
            if (self.current.isOp()
                and this_prec.gte(prec)) {
                // Unreachable since we theoretically guarantee `isOp` means
                // this `fromTag` works.
                const op_kind = try Value.BinaryOp.Kind.fromTag(self.current.tag);
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

                lhs = Value.initBinary(op_kind, lhs_ptr, rhs_ptr);
            } else {
                return lhs;
            }
        }
    }

    // Parses an identifier as a value
    fn parseIdentifier(self: *Self) ParseError!Value {
        try self.consume(.identifier, error.ExpectedIdentifier);
        const name = self.lexer.getTokString(self.previous);
        return Value.initAccessName(name);
    }

    fn parseLiteral(self: *Self) ParseError!Value {
        return if (self.current.tag == .true_ or self.current.tag == .false_)
            try self.parseBoolean()
        else if (self.current.tag == .num)
            try self.parseNumber()
        else
            error.NotALiteral;
    }

    fn parseBoolean(self: *Self) ParseError!Value {
        return if (self.match(.true_))
            Value.initBool(true)
        else if (self.match(.false_))
            Value.initBool(false)
        else
            error.NotABoolean;
    }

    fn parseNumber(self: *Self) ParseError!Value {
        try self.consume(.num, error.ExpectedNumber);
        const num_str = self.lexer.getTokString(self.previous);
        // No floats yet
        const num = if (std.fmt.parseInt(i32, num_str, 10)) |num|
                num
            else |_|
                return error.NotANumber;
        return Value.initInt(num);
    }

    fn diagCurrent(self: Self, err: ParseError) void {
        self.diag(self.lexer.getTokString(self.current), err);
    }

    fn diagPrevious(self: Self, err: ParseError) void {
        self.diag(self.lexer.getTokString(self.previous), err);
    }

    fn diag(self: Self, tok: []const u8, err: ParseError) void {
        _ = self;
        // TODO: Make this better :)
        std.debug.print("\nError at token {s}: {}\n", .{ tok, err });
    }

    fn bindingPower(tag: Token.Tag) Precedence {
        return switch (tag) {
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
