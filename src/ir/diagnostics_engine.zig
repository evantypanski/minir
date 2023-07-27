const std = @import("std");

const fmt = std.fmt;
const Writer = @import("std").fs.File.Writer;

const Program = @import("nodes/program.zig").Program;
const Stmt = @import("nodes/statement.zig").Stmt;
const VarDecl = @import("nodes/statement.zig").VarDecl;
const Value = @import("nodes/value.zig").Value;
const Type = @import("nodes/type.zig").Type;
const BasicBlock = @import("nodes/basic_block.zig").BasicBlock;
const Decl = @import("nodes/decl.zig").Decl;
const Function = @import("nodes/decl.zig").Function;
const ParseError = @import("errors.zig").ParseError;
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

    pub fn diag(self: Self, err: ParseError, loc: Loc) void {
        const start = self.startLineLoc(loc);
        const end = self.endLineLoc(loc);
        std.debug.print(
            "\nerror: {s}:{} {}\n{s}\n",
            .{
                self.source_mgr.filename,
                self.source_mgr.getLineNum(loc.start),
                err,
                self.source_mgr.snip(start, end)
            }
        );
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
