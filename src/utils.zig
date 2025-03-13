const std = @import("std");
const Type = std.builtin.Type;
const Elem = std.meta.Elem;

fn consty_ptr(comptime collection: type) type {
    const info = @typeInfo(collection);
    std.debug.assert(info == .pointer);
    comptime if (info == .array) {
        @compileError("arrays cannot be indexed");
    };

    const T = Elem(collection);

    var t = @typeInfo(*T);

    t.pointer.is_const = info.pointer.is_const;

    return @Type(t);
}

pub inline fn get(slice: anytype, idx: usize) error{OutOfBounds}!consty_ptr(@TypeOf(slice)) {
    if (idx >= slice.len) return error.OutOfBounds;
    return &slice[idx];
}

test "utils get" {
    const testing = std.testing;

    var ar: [3]u8 = .{ 0, 1, 2 };

    const a = try get(ar[0..], 0);
    try std.testing.expect(a.* == ar[0]);
    const b = get(&ar, 15);
    try std.testing.expectError(error.OutOfBounds, b);

    const e: [3]u8 = .{ 0, 1, 2 };
    const c = try get(&e, 1);
    try testing.expect(c.* == e[1]);
}

inline fn field_name_from_type(comptime un: type, comptime field: type) [*:0]const u8 {
    const fields = switch(@typeInfo(un)) {
        .@"union" => |u| u.fields,
        else => @compileError("expected a union, got " ++ @typeName(un)),
    };

    for (fields) |f| {
        if (f.type == field) {
            return f.name;
        }
    }

    @compileError("the union " ++ @typeName(un) ++ " does not have a field of type " ++ @typeName(field));
}

pub fn raw_union_to_tagged(comptime tagT: type, comptime rawT: type, comptime taggedT: type, tag: tagT, raw: rawT) taggedT {
    const Tag = std.meta.Tag;
    if (tagT != Tag(taggedT)) {
        @compileError("tag of the raw union is not the same as the taggged; " ++ @typeName(tagT) ++ " != " ++ @typeName(Tag(taggedT)));
    }

    inline for (@typeInfo(tagT).@"enum".fields) |tag_field| {
        if (@intFromEnum(tag) == tag_field.value) {
            var tagged: taggedT = undefined;
            const T = @TypeOf(@field(tagged, tag_field.name));
            @field(tagged, tag_field.name) = @field(raw, field_name_from_type(rawT, T));

            return tagged;
        }
    }

    @compileError("bruh");
}

