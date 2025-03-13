const std = @import("std");

pub fn raw_union_to_tagged(comptime tagT: type, comptime rawT: type, comptime taggedT: type, comptime convert: fn (*const rawT, *taggedT) void, tag: tagT, raw: rawT) taggedT {
    if (tagT != std.meta.Tag(taggedT)) {
        @compileError("tag of the raw union is not the same as the taggged; " ++ @typeName(tagT) ++ " != " ++ @typeName(std.meta.Tag(taggedT)));
    }

    inline for (@typeInfo(tagT).@"enum".fields) |tag_field| {
        const t: tagT = @enumFromInt(tag_field.value);
        if (t == tag) {
            var tagged = @unionInit(taggedT, tag_field.name, undefined);
            convert(&raw, &tagged);
            return tagged;
        }
    }
}


