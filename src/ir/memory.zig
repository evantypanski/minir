//! This is not exactly production grade memory management which requests
//! memory from the OS. It's a mix between what a "real" heap would do and
//! using the Zig library features.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Value = @import("nodes/value.zig").Value;
const HeapError = @import("errors.zig").HeapError;

const HEAP_MAX: usize = 1000;

pub const BlockMeta = struct {
    size: usize,
    next: ?*align(1) BlockMeta,
    free: bool,

    pub fn init(size: usize) BlockMeta {
        return .{
            .size = size,
            .next = null,
            .free = true,
        };
    }
};

/// For the heap, all sizes are based on Values, not on bytes.
pub const Heap = struct {
    const Self = @This();
    global_base: ?*align(1) BlockMeta,
    next_idx: usize,
    memory: [HEAP_MAX]u8,

    pub fn init() !Self {
        return .{
            .global_base = null,
            .next_idx = 0,
            .memory = [_]u8{0} ** HEAP_MAX,
        };
    }

    fn find_free_block(self: Self, last: *?*align(1) BlockMeta, size: usize) ?*align(1) BlockMeta {
        var opt_current = self.global_base;
        while (opt_current) |current| {
            if (current.*.free and current.*.size >= size) {
                break;
            }

            last.* = current;
            opt_current = current.*.next;
        }

        return opt_current;
    }

    fn block_cast(self: *Self, ptr: usize) *align(1) BlockMeta {
        return std.mem.bytesAsValue(BlockMeta, self.memory[ptr..][0..@sizeOf(BlockMeta)]);
    }

    fn request_space(self: *Self, last: ?*align(1) BlockMeta, size: usize) !usize {
        const size_with_meta = size + @sizeOf(BlockMeta);
        // Since we aren't moving/combining allocations this is simple
        if (HEAP_MAX - self.next_idx < size_with_meta) {
            return HeapError.Bad;
        }

        const block_i = self.next_idx;
        self.next_idx += size_with_meta;
        const block = self.block_cast(block_i);
        block.* = BlockMeta.init(size);
        if (last) |b| {
            b.next = block;
        }


        return block_i;
    }

    pub fn alloc(self: *Self, size: usize) !usize {
        if (size <= 0) {
            return HeapError.Bad;
        }
        var ptr: usize = undefined;
        var block: ?*align(1) BlockMeta = undefined;

        if (self.global_base == null) {
            ptr = try self.request_space(null, size);
            block = self.block_cast(ptr);
            if (block == null) {
                return HeapError.Bad;
            }

            self.global_base = block;
        } else {
            var last = self.global_base;
            block = self.find_free_block(&last, size);
            if (block) |b| {
                // Could split block here
                b.*.free = false;
            } else {
                ptr = try self.request_space(last, size);
                block = self.block_cast(ptr);
                if (block == null) {
                    return HeapError.Bad;
                }
            }
        }

        return ptr + @sizeOf(BlockMeta);
    }

    fn get_block_ptr(self: *Self, ptr: usize) *align(1) BlockMeta {
        return self.block_cast(ptr - @sizeOf(BlockMeta));
    }

    pub fn free(self: *Self, ptr: usize) void {
        var block = self.get_block_ptr(ptr);
        block.free = true;
    }
};
