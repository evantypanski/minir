const std = @import("std");

const Program = @import("nodes/program.zig").Program;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Value = @import("nodes/value.zig").Value;

pub const ParseError = error {
    Unexpected,
    ExpectedNumber,
};

pub const Parser = struct {
    const Self = @This();

    const Precedence = enum(u8) {
        NONE,
        ASSIGN,
        OR,
        AND,
        EQUAL,
        COMPARE,
        TERM,
        FACTOR,
        UNARY,
        CALL,
        PRIMARY,

        pub fn gte(self: Precedence, other: Precedence) bool {
            return @enumToInt(self) >= @enumToInt(other);
        }

        pub fn inc(self: Precedence) Precedence {
            if (self == .PRIMARY) {
                return .PRIMARY;
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
            .current = Token.init(.NONE, 0, 0),
            .previous = Token.init(.NONE, 0, 0),
        };
    }

    pub fn parse(self: *Self) void {
        // We expect to be at the beginning. So we must advance once.
        if (!self.current.isValid()) {
            self.advance();
        }

        // A program is just a bunch of function decls.
        while (self.current.tag != .EOF) : (self.advance()) {
            self.parseFnDecl();
        }
    }

    fn advance(self: *Self) void {
        self.previous = self.current;
        // Lex until valid token
        while(true) {
            if (self.lexer.lex()) |tok| {
                self.current = tok;
                return;
            } else |err| switch (err) {
                // TODO: This diagnoses the previous token. Oops
                error.Unexpected => self.diagCurrent("Unable to lex token"),
            }
        }
    }

    fn consume(self: *Self, tag: Token.Tag, error_message: []const u8) void {
        if (self.current.tag == tag) {
            self.advance();
            return;
        }

        self.diagCurrent(error_message);
    }

    fn parseFnDecl(self: *Self) void {
        self.consume(.FN, "Expected 'fn' keyword");
        self.consume(.AT, "Expected '@' before function identifier");
        // TODO: Store identifier name
        self.consume(.IDENTIFIER, "Expected identifier after '@'");
        self.consume(.LPAREN, "Expected left paren to start function parameters");
        // TODO: Arguments
        self.consume(.RPAREN, "Expected right paren after parameters");
        // Return
        self.consume(.ARROW, "Expected arrow to signify return type");
        // TODO: Store identifier name
        self.consume(.IDENTIFIER, "Expected return type");

        self.consume(.LBRACE, "Expected left brace to start function body");

        while (self.current.tag != .RBRACE and self.current.tag != .EOF) {
            self.parseStmt();
        }

        // If we get here without right brace it's EOF
        self.consume(.RBRACE, "Unexpected end of file");
    }

    fn parseStmt(self: *Self) void {
        if (self.match(.DEBUG)) {
            self.parseDebug();
        } else {
            _ = self.parseExpr() catch self.diagCurrent("Error parsing expression");
        }
    }

    fn parseDebug(self: *Self) void {
        self.consume(.LPAREN, "Expected 'fn' keyword");
        _ = self.parseExpr() catch self.diagCurrent("Error parsing expression");
        self.consume(.RPAREN, "Expected 'fn' keyword");
    }

    fn parseExpr(self: *Self) !Value {
        return try self.parsePrecedence(.ASSIGN);
    }

    fn parsePrecedence(self: *Self, prec: Precedence) !Value {
        // Just abort for non-numbers for now
        if (self.current.tag != .NUM) {
            return error.ExpectedNumber;
        }

        var lhs = try self.parseNumber();

        while (true) {
            const this_prec = bindingPower(self.current.tag);
            if (self.current.isOp()
                and this_prec.gte(prec)) {
                // Unreachable since we theoretically guarantee `isOp` means
                // this `fromTag` works.
                const op_kind = Value.BinaryOp.Kind.fromTag(self.current.tag)
                    catch unreachable;
                self.advance();
                var rhs = try self.parsePrecedence(this_prec.inc());
                lhs = Value.initBinary(op_kind, &lhs, &rhs);
            } else {
                return lhs;
            }
        }
    }

    fn parseNumber(self: *Self) !Value {
        self.consume(.NUM, "Expected number");
        const num_str = self.lexer.getTokString(self.previous);
        // No floats yet
        const num = try std.fmt.parseInt(i32, num_str, 10);
        return Value.initInt(num);
    }

    fn diagCurrent(self: Self, message: []const u8) void {
        self.diag(self.current, message);
    }

    fn diag(self: Self, token: Token, message: []const u8) void {
        // TODO: Make this better :)
        std.debug.print(
            "\nError at token {s}: {s}\n",
            .{
                self.lexer.getTokString(token),
                message
            }
        );
    }

    fn bindingPower(tag: Token.Tag) Precedence {
        return switch (tag) {
            .EQ => .ASSIGN,
            .PIPE_PIPE => .OR,
            .AMP_AMP => .AND,
            .EQ_EQ => .EQUAL,
            .LESS, .LESS_EQ, .GREATER, .GREATER_EQ => .COMPARE,
            .PLUS, .MINUS => .TERM,
            .STAR, .SLASH => .FACTOR,
            else => .NONE,
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
