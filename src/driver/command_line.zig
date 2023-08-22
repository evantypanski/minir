const std = @import("std");
const Writer = std.fs.File.Writer;

pub const ParseError = error {
    UnknownCommand,
};

pub const CommandLine = struct {
    const Self = @This();

    const Command = enum {
        interpret,
        fmt,
        dump,
        none,
    };

    pub const CommandLineResult = union(Command) {
        interpret: InterpretConfig,
        fmt: FmtConfig,
        dump: DumpConfig,
        none,

        pub fn filename(self: CommandLineResult) ?[]const u8 {
            return switch (self) {
                .interpret => |config| config.filename,
                .fmt => |config| config.filename,
                .dump => |config| config.filename,
                .none => null,
            };
        }
    };

    pub const InterpretConfig = struct {
        filename: ?[]const u8,
        interpreter_type: enum { byte, treewalk },

        pub fn default() InterpretConfig {
            return .{
                .filename = null,
                .interpreter_type = .byte,
            };
        }
    };

    pub const FmtConfig = struct {
        filename: ?[]const u8,

        pub fn default() FmtConfig {
            return .{
                .filename = null,
            };
        }
    };

    pub const DumpConfig = struct {
        filename: ?[]const u8,

        pub fn default() DumpConfig {
            return .{
                .filename = null,
            };
        }
    };

    allocator: std.mem.Allocator,
    writer: Writer,
    // Command line owns the command line arguments and will deinit them
    // with deinit()
    args: [][:0]u8,

    pub fn init(allocator: std.mem.Allocator, writer: Writer) !Self {
        return .{
            .allocator = allocator,
            .writer = writer,
            .args = try std.process.argsAlloc(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        std.process.argsFree(self.allocator, self.args);
    }

    fn printHelp(self: Self) !void {
        try self.writer.writeAll(
            \\minir (miniature IR) usage:
            \\  minir [command] [options] [filename]
            \\
            \\Commands:
            \\  interpret       Interpret the program (defaults to bytecode)
            \\  dump            Dump the program's bytecode
            \\  fmt             Format file
            \\
            \\For help with a given command, use --help after that command:
            \\  minir interpret --help
            \\
            \\
        );
    }

    fn printInterpretHelp(self: Self) !void {
        try self.writer.writeAll(
            \\minir (miniature IR) interpret usage:
            \\  minir interpret [options] [filename]
            \\
            \\Options:
            \\  --byte, -b      Use the bytecode interpreter (default)
            \\  --treewalk, -t  Use the treewalk interpreter
            \\
            \\
        );
    }

    fn printFmtHelp(self: Self) !void {
        try self.writer.writeAll(
            \\minir (miniature IR) fmt usage:
            \\  minir fmt [options] [filename]
            \\
            \\Options:
            \\  None yet!
            \\
            \\
        );
    }

    fn printDumpHelp(self: Self) !void {
        try self.writer.writeAll(
            \\minir (miniature IR) dump usage:
            \\  minir dump [options] [filename]
            \\
            \\Options:
            \\  None yet!
            \\
            \\
        );
    }

    fn parseCommand(arg: []const u8) ParseError!Command {
        return if (std.mem.eql(u8, arg, "interpret"))
            .interpret
        else if (std.mem.eql(u8, arg, "fmt"))
            .fmt
        else if (std.mem.eql(u8, arg, "dump"))
            .dump
        else
            error.UnknownCommand;
    }

    fn parseInterpret(self: Self) !CommandLineResult {
        if (self.args.len <= 2) {
            try self.printInterpretHelp();
            return .none;
        }

        var config = InterpretConfig.default();
        for (self.args[2..]) |arg| {
            if (arg[0] == '-') {
                if (arg.len < 2) {
                    try unknownOption(arg);
                    continue;
                }

                if (arg[1] == 'b' or std.mem.eql(u8, arg, "--byte")) {
                    config.interpreter_type = .byte;
                } else if (arg[1] == 't' or std.mem.eql(u8, arg, "--treewalk")) {
                    config.interpreter_type = .treewalk;
                } else if (arg[1] == 'h' or std.mem.eql(u8, arg, "--help")) {
                    try self.printInterpretHelp();
                    return .none;
                } else {
                    try unknownOption(arg);
                }
            } else {
                if (config.filename) |old_filename| {
                    try multipleFilenames(arg, old_filename);
                }
                config.filename = arg;
            }
        }

        return .{ .interpret = config };
    }

    fn parseFmt(self: Self) !CommandLineResult {
        if (self.args.len <= 2) {
            try self.printFmtHelp();
            return .none;
        }

        var config = FmtConfig.default();
        for (self.args[2..]) |arg| {
            if (arg[0] == '-') {
                if (arg.len < 2) {
                    try unknownOption(arg);
                    continue;
                }

                if (arg[1] == 'h' or std.mem.eql(u8, arg, "--help")) {
                    try self.printFmtHelp();
                    return .none;
                } else {
                    try unknownOption(arg);
                }
            } else {
                if (config.filename) |old_filename| {
                    try multipleFilenames(arg, old_filename);
                }
                config.filename = arg;
            }
        }

        return .{ .fmt = config };
    }

    fn parseDump(self: Self) !CommandLineResult {
        if (self.args.len <= 2) {
            try self.printDumpHelp();
            return .none;
        }

        var config = DumpConfig.default();
        for (self.args[2..]) |arg| {
            if (arg[0] == '-') {
                if (arg.len < 2) {
                    try unknownOption(arg);
                    continue;
                }

                if (arg[1] == 'h' or std.mem.eql(u8, arg, "--help")) {
                    try self.printDumpHelp();
                    return .none;
                } else {
                    try unknownOption(arg);
                }
            } else {
                if (config.filename) |old_filename| {
                    try multipleFilenames(arg, old_filename);
                }
                config.filename = arg;
            }
        }

        return .{ .dump = config };
    }

    fn unknownOption(arg: []const u8) !void {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Unknown option '{s}'\n", .{arg});
    }

    fn multipleFilenames(new_filename: []const u8, old_filename: []const u8) !void {
        const stderr = std.io.getStdErr().writer();
        try stderr.print(
            \\Found filename '{s}' but already have '{s}'.
            \\Please specify one file name at a time.
            \\
             , .{new_filename, old_filename}
        );
    }

    pub fn parse(self: Self) !CommandLineResult {
        if (self.args.len == 1) {
            try self.printHelp();
            return .none;
        }

        const command = try parseCommand(self.args[1]);
        return switch (command) {
            .interpret => self.parseInterpret(),
            .fmt => self.parseFmt(),
            .dump => self.parseDump(),
            .none => .none,
        };
    }
};
