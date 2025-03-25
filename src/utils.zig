const std = @import("std");
const Type = std.builtin.Type;
const Elem = std.meta.Elem;

pub const slices = struct {
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
};

pub const structs = struct {
    pub inline fn sum_bit_size(comptime T: type) usize {
        const info = @typeInfo(T);

        if (info != .@"struct") {
            @compileError(@typeName(T) ++ " is not a struct");
        }

        var bit_size: usize = 0;

        inline for (info.@"struct".fields) |f| {
            bit_size += @bitSizeOf(f.type);
        }

        return bit_size;
    }

    pub inline fn pack_struct(comptime T: type) type {
        var info = @typeInfo(T);

        if (info != .@"struct") {
            @compileError(@typeName(T) ++ " is not a struct");
        }
        if (info.@"struct".layout == .@"extern") {
            @compileError("extern structs not supported");
        }

        info.@"struct".layout = .@"packed";
        var fields: [info.@"struct".fields.len]std.builtin.Type.StructField = undefined;

        for (0..fields.len) |i| {
            fields[i] = info.@"struct".fields[i];
            fields[i].alignment = 0;
        }

        info.@"struct".fields = &fields;

        return @Type(info);
    }

    pub inline fn copy(src: anytype, comptime dst: type) dst {
        const src_info = @typeInfo(@TypeOf(src));
        const dst_info = @typeInfo(dst);

        if (src_info != .@"struct" or dst_info != .@"struct") {
            @compileLog(src_info);
            @compileLog(dst_info);
            @compileError("arguments to copy must be both structs");
        }

        var tmp: dst = undefined;

        inline for (src_info.@"struct".fields) |field| {
            const name = field.name;
            @field(tmp, name) = @field(src, name);
        }

        return tmp;
    }
};
