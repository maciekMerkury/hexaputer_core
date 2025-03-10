const std = @import("std");
const Type = std.builtin.Type;

fn consty_ptr(comptime collection: type) type {
    const info = @typeInfo(collection);
    std.debug.assert(info == .Pointer);
    comptime if (info == .Array) {
        @compileError("arrays cannot be indexed");
    };

    const T = if (info.Pointer.size == .One) @typeInfo(info.Pointer.child).Array.child
                else info.Pointer.child;

    var t = @typeInfo(*T);

    t.Pointer.is_const = info.Pointer.is_const;

    return @Type(t);
}

pub inline fn get(slice: anytype, idx: usize) error{OutOfBounds}!consty_ptr(@TypeOf(slice)) {
    if (idx >= slice.len) return error.OutOfBounds;
    return &slice[idx];
}

test "utils get" {
    const testing = std.testing;

    var ar: [3]u8 = .{0, 1, 2};

    const a = try get(ar[0..], 0);
    try std.testing.expect(a.* == ar[0]);
    const b = get(&ar, 15);
    try std.testing.expectError(error.OutOfBounds, b);

    const e: [3]u8 = .{0, 1, 2};
    const c = try get(&e, 1);
    try testing.expect(c.* == e[1]);
}
