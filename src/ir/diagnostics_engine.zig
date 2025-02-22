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

    pub fn err(self: Self, comptime the_err: anyerror, args: anytype, loc: Loc) void {
        const start = self.startLineLoc(loc);
        const end = self.endLineLoc(loc);
        // Lol formatting
        const all_args = .{
            self.source_mgr.filename,
            self.source_mgr.getLineNum(start),
        } ++ args ++ .{
            self.source_mgr.snip(start, end),
        };
        // TODO: I really want a caret at the location of the offending loc in
        // the snippet, but the log function doesn't seem capable for that
        // runtime info. We can't concat the string or get the underlying writer,
        // nor use the fill characters since that has to be comptime. We could
        // use an allocator but why would we pass an allocator in here? I'd
        // rather avoid that if possible. We can't do it in a new message
        // since `std.log` adds 'error:' before the message
        const msg = if (comptime getErrStr(the_err)) |str|
            "at {?s}:{}: " ++ str ++ "\n{s}"
        else
            "at {s}:{}:\n{s}";

        std.log.err(msg, all_args);
    }

    /// Diagnoses the number of errors from a given component
    pub fn diagNumErrors(self: Self, num: usize, name: []const u8) void {
        _ = self;
        std.debug.print("\n\nFound {} errors during {s}\n", .{ num, name });
    }

    /// Finds the start of the line for a Loc
    fn startLineLoc(self: Self, loc: Loc) usize {
        if (loc.start == 0) return 0;
        var line_start = loc.start - 1;
        while (line_start > 0 and self.source_mgr.get(line_start) != '\n') : (line_start -= 1) {}

        return line_start + 1;
    }

    /// Finds the end of the line for a Loc
    fn endLineLoc(self: Self, loc: Loc) usize {
        var line_end = loc.end;
        while (line_end < self.source_mgr.len() and self.source_mgr.get(line_end) != '\n') : (line_end += 1) {}

        return line_end;
    }

    /// Gets the format string for a given error. Any unimplemented errors expect
    /// three format string arguments: the file name, the line number, and the
    /// code snippet.
    fn getErrStr(comptime found_error: anyerror) ?[]const u8 {
        return switch (found_error) {
            error.InvalidType => "{s} is an invalid type for '{s}'",
            error.IncompatibleTypes => "type {s} of '{s}' is incompatible with type {s} of '{s}'",
            error.Expected => "expected '{s}' token",
            error.NotABranch => "'{s}' is not a branch keyword",
            error.NotANumber => "'{s}' is not a valid number",
            error.BadArity => "call to '{s}' expected {} argument(s); found {}",
            error.Unresolved => "unresolved variable access to '{s}'",
            error.KeywordInvalidIdentifier => "'{s}' is a keyword and cannot be used as an identifier",
            error.InvalidTypeName => "'{s}' is not a valid type name",
            else => null,
        };
    }
};
