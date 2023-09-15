const std = @import("std");

const fmt = std.fmt;
const Writer = @import("std").fs.File.Writer;

const Program = @import("nodes/program.zig").Program;
const Stmt = @import("nodes/statement.zig").Stmt;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Type = @import("nodes/type.zig").Type;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;
const ParseError = @import("errors.zig").ParseError;
const TypecheckError = @import("errors.zig").TypecheckError;
const Loc = @import("sourceloc.zig").Loc;
const SourceManager = @import("source_manager.zig").SourceManager;

pub const Diagnostics = struct {
    const Self = @This();

    // Diagnostics does not own the source.
    source_mgr: SourceManager,

    pub fn init(source_mgr: SourceManager) Self {
        return .{
            .source_mgr = source_mgr,
        };
    }

    // All of this diag* methods should eventually be replaced with some
    // comptime string manip stuff. But I don't feel like doing that yet
    // so instead for each unique diagnostic format there's a new method.
    // :)
    pub fn diagParse(self: Self, err: ParseError, loc: Loc) void {
        const start = self.startLineLoc(loc);
        const end = self.endLineLoc(loc);
        std.debug.print(
            "\nparsing error: {s}:{} {}\n{s}\n",
            .{
                self.source_mgr.filename,
                self.source_mgr.getLineNum(loc.start),
                err,
                self.source_mgr.snip(start, end)
            }
        );
    }

    pub fn diagIncompatibleTypes(
        self: Self, err: TypecheckError, loc1: Loc, loc2: Loc
    ) void {
        // TODO: Line numbers if it spans multiple? Right now it just does
        // first which isn't the worst thing ever
        const start_line = self.startLineLoc(loc1);
        const end_line = self.endLineLoc(loc2);
        std.debug.print(
            "\nincompatible types at {s}:{} {}: {s} and {s} are not the same type\n{s}\n",
            .{
                self.source_mgr.filename,
                self.source_mgr.getLineNum(loc1.start),
                err,
                self.source_mgr.snip(loc1.start, loc1.end),
                self.source_mgr.snip(loc2.start, loc2.end),
                self.source_mgr.snip(start_line, end_line)
            }
        );
    }

    /// Diagnoses the number of errors from a given component
    pub fn diagNumErrors(self: Self, num: usize, name: []const u8) void {
        _ = self;
        std.debug.print( "\n\nFound {} errors during {s}\n", .{ num, name });
    }

    /// Finds the start of the line for a Loc
    fn startLineLoc(self: Self, loc: Loc) usize {
        var line_start = loc.start - 1;
        while (line_start > 0 and self.source_mgr.get(line_start) != '\n')
            : (line_start -= 1) {}

        return line_start + 1;
    }

    /// Finds the end of the line for a Loc
    fn endLineLoc(self: Self, loc: Loc) usize {
        var line_end = loc.end;
        while (line_end < self.source_mgr.len() and self.source_mgr.get(line_end) != '\n')
            : (line_end += 1) {}

        return line_end;
    }
};
