const std = @import("std");

pub const Config = enum {
    interpret,
    fmt,
    dump,
    none,
};

pub const Options = union(Config) {
    interpret: InterpretConfig,
    fmt: FmtConfig,
    dump: DumpConfig,
    none,

    pub fn filename(self: Options) ?[]const u8 {
        return switch (self) {
            .interpret => |config| config.filename,
            .fmt => |config| config.filename,
            .dump => |config| config.filename,
            .none => null,
        };
    }
};

pub const InterpreterType = enum {
    byte,
    treewalk,
    binary
};

pub const InterpretConfig = struct {
    filename: ?[]const u8,
    interpreter_type: InterpreterType,

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
    format: DumpFormat,

    const DumpFormat = enum {
        binary,
        debug,
        json,
    };

    pub fn default() DumpConfig {
        return .{
            .filename = null,
            .format = .binary,
        };
    }
};

