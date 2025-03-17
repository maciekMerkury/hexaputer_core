const std = @import("std");

pub const cpu = @import("cpu.zig");
pub const instruction = @import("instruction.zig");
const utils = @import("utils.zig");

test {
    const testing = std.testing;
    testing.refAllDeclsRecursive(@This());
}
