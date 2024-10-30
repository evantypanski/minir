const std = @import("std");

const Writer = std.fs.File.Writer;
const Options = @import("options.zig").Options;
const Config = @import("options.zig").Config;
const InterpretConfig = @import("options.zig").InterpretConfig;
const FmtConfig = @import("options.zig").FmtConfig;
const DumpConfig = @import("options.zig").DumpConfig;

pub const ParseError = error {
    UnknownCommand,
};

pub const CommandLine = struct {
    const Self = @This();

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
            \\  --binary        When using the bytecode interpreter, treat the
            \\                  file as a binary (bytecode) file
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
            \\  --debug, -d     Dump in a human readable, debug format
            \\  --binary, -b    Dump in a binary format (default)
            \\  --json          Dump in JSON
            \\
            \\
        );
    }

    fn parseCommand(arg: []const u8) ParseError!Config {
        return if (std.mem.eql(u8, arg, "interpret"))
            .interpret
        else if (std.mem.eql(u8, arg, "fmt"))
            .fmt
        else if (std.mem.eql(u8, arg, "dump"))
            .dump
        else
            error.UnknownCommand;
    }

    fn parseInterpret(self: Self) !Options {
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
                } else if (std.mem.eql(u8, arg, "--binary")) {
                    config.interpreter_type = .binary;
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

    fn parseFmt(self: Self) !Options {
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

    fn parseDump(self: Self) !Options {
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
                } if (arg[1] == 'd' or std.mem.eql(u8, arg, "--debug")) {
                    config.format = .debug;
                } if (arg[1] == 'b' or std.mem.eql(u8, arg, "--binary")) {
                    config.format = .binary;
                } if (std.mem.eql(u8, arg, "--json")) {
                    config.format = .json;
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

    pub fn parse(self: Self) !Options {
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
