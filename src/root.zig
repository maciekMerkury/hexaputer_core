const std = @import("std");
const k = std.builtin.Type;

pub const cpu = @import("cpu.zig");
pub const instruction = @import("instruction.zig");
pub const new_instruction = @import("new_instructions.zig");
const utils = @import("utils.zig");

test {
    const testing = std.testing;
    testing.refAllDeclsRecursive(@This());
}

