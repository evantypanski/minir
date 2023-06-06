const std = @import("std");
const ArrayList = std.ArrayList;

const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig").Value;
const OpCode = @import("opcodes.zig").OpCode;
const array_size = @import("interpret.zig").array_size;

pub const Verifier = struct {
    const Self = @This();

    chunk: Chunk,

    // sp is signed here so we can detect underflows easier
    sp: isize,
    idx: usize,
    num_errors: usize,

    pub fn init(chunk: Chunk) Self {
        return .{
            .chunk = chunk,
            .sp = 0,
            .idx = 0,
            .num_errors = 0,
        };
    }

    pub fn verify(self: *Self) bool {
        while (self.idx < self.chunk.bytes.len) : (self.idx += 1) {
            const byte = self.chunk.bytes[self.idx];
            if (!isOpcode(byte)) {
                self.diag("Not an opcode {}\n", .{byte});
                continue;
            }
            const op = @intToEnum(OpCode, byte);
            if (self.sp + op.stackEffect() < 0) {
                self.diag("Underflowing stack!\n", .{});
            }
            self.sp += op.stackEffect();
            if (self.sp >= array_size) {
                self.diag("Overflowing stack!\n", .{});
            }

            self.idx += op.numImmediates();
        }

        if (self.num_errors > 0) {
            std.debug.print("Bytecode had {} errors", .{self.num_errors});
            return false;
        }

        return true;
    }

    pub fn isOpcode(byte: u8) bool {
        comptime var i: usize = 0;
        const enum_info = @typeInfo(OpCode).Enum;
        // TODO: Can we do some sort of comptime map on the fields to check
        // this? Inline makes it ok but this could be more like a switch
        inline while (i < enum_info.fields.len) : (i += 1) {
            if (byte == enum_info.fields[i].value) {
                return true;
            }
        }
        return false;
    }

    fn diag(self: *Self, comptime msg: []const u8, args: anytype) void {
        self.num_errors += 1;
        // TODO: This will have a separate writer/engine/whatever
        std.debug.print(msg, args);
    }
};
