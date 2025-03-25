const std = @import("std");
const cpu = @import("cpu.zig");
const utils = @import("utils.zig");
const Register = cpu.Register;
const Word = cpu.Word;

pub const InstructionType = enum(u4) {
    /// stops execution (there are not interupts)
    halt,
    /// the next maths op will be signed
    signed,
    /// switches between memory addressing and mmio
    address_switch,

    inc,
    dec,
    not,

    /// normal branch is just load into isp
    branchIfZero,

    store,
    load,
    add,
    sub,
    mul,
    div,
    @"and",
    @"or",

    move,
};

pub const Instruction = union(InstructionType) {
    halt,
    signed,
    address_switch,

    inc: Register,
    dec: Register,
    not: Register,

    branchIfZero: Mem,

    store: RegReg,
    load: RegReg,
    add: RegReg,
    sub: RegReg,
    mul: RegReg,
    div: RegReg,
    @"and": RegReg,
    @"or": RegReg,

    move: Move,

    pub const Move = struct {
        src: union(enum) {
            reg: Register,
            @"const": Word,
        },
        dst: Register,
    };

    pub const RegReg = struct {
        src: Register,
        dst: Register,
    };

    pub const Mem = struct {
        reg: Register,
        ptr: Word,
    };

    pub const MaxByteLen: usize = @bitSizeOf(BinaryInstruction) / 8;
    comptime {
        if (MaxByteLen != 3) {
            @compileError("Instruction.MaxByteLen must aways be 3, but is " ++ MaxByteLen);
        }
    }

    /// the byt elen of the entire instruction, including the tag
    pub inline fn byte_count(self: *const @This()) usize {
        return byte_size(self.*, self.* == .move and self.move.src == .reg);
    }

    // ugly as fuck, but idk how to do it better
    pub fn pack(self: *const @This()) BinaryInstruction {
        const Payload = BinaryInstruction.Payload;
        return .{
            .type = self.*,
            .payload = switch (self.*) {
                .halt, .signed, .address_switch => undefined,
                .inc, .dec, .not => |reg| .{ .reg = reg },
                .branchIfZero => |mem| .{ .mem = utils.structs.copy(mem, @FieldType(Payload, "mem")) },
                .store, .load, .add, .sub, .mul, .div, .@"and", .@"or" => |regreg| .{ .reg_reg = utils.structs.copy(regreg, @FieldType(Payload, "reg_reg")) },
                .move => |move| .{ .move = .{
                    .is_reg = (move.src == .reg),
                    .src = switch (move.src) {
                        .reg => |reg| .{ .reg = reg },
                        .@"const" => |word| .{ .@"const" = word },
                    },
                    .dst = move.dst,
                } },
            },
        };
    }
};

pub const BinaryInstruction = packed struct {
    type: InstructionType,
    payload: Payload,
    pub const Payload = packed union {
        move: packed struct {
            is_reg: bool,
            src: packed union {
                reg: Register,
                @"const": Word,
            },
            dst: Register,

            pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                try writer.print("move{{ .src = ", .{});

                if (value.is_reg) {
                    try writer.print("{}", .{value.src.reg});
                } else {
                    try writer.print("{}", .{value.src.@"const"});
                }

                try writer.print(", .dst = {}}}", .{value.dst});
            }
        },

        reg: Register,
        mem: utils.structs.pack_struct(Instruction.Mem),
        reg_reg: utils.structs.pack_struct(Instruction.RegReg),
        nothing: void,
    };

    /// returns the number of bytes that have to be read to read the entire instruction
    pub inline fn bytes_left(byte: u8) usize {
        const Tmp = packed struct(u8) {
            type: InstructionType,

            /// only valid if type == .move
            is_reg: bool,
            _: u3,
        };

        const inst: Tmp = @bitCast(byte);

        return byte_size(inst.type, inst.type == .move and inst.is_reg) - 1;
    }

    pub inline fn byte_count(self: *const @This()) usize {
        return byte_size(self.type, self.type == .move and self.payload.move.is_reg);
    }

    pub fn eql(self: @This(), other: @This()) bool {
        if (self.type != other.type)
            return false;

        return switch (self.type) {
            .halt, .signed, .address_switch => true,
            .inc, .dec, .not => self.payload.reg == other.payload.reg,
            .branchIfZero => std.meta.eql(self.payload.mem, other.payload.mem),

            .store, .load, .add, .sub, .mul, .div, .@"and", .@"or" => std.meta.eql(self.payload.reg_reg, other.payload.reg_reg),

            .move => std.meta.eql(self.payload.move, other.payload.move),
        };
    }

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("BinaryInstruction{{ .type = {}, .payload = ", .{value.type});
        try switch (value.type) {
            .halt, .signed, .address_switch => writer.print("{}", .{value.payload.nothing}),
            .inc, .dec, .not => writer.print("{}", .{value.payload.reg}),
            .branchIfZero => writer.print("{}", .{value.payload.mem}),
            .store, .load, .add, .sub, .mul, .div, .@"and", .@"or" => writer.print("{}", .{value.payload.reg_reg}),
            .move => writer.print("{}", .{value.payload.move}),
        };
        return writer.print(" }}", .{});
    }

    // pub fn upack(self: *const @This()) Instruction {
    //     std.builtin.Type.UnionField
    // }
};

fn byte_size(t: InstructionType, is_reg: bool) usize {
    var bit_size: usize = @bitSizeOf(InstructionType);
    bit_size += switch (t) {
        .halt, .signed, .address_switch => 0,
        .inc, .dec, .not => @bitSizeOf(Register),
        .branchIfZero => utils.structs.sum_bit_size(Instruction.Mem),
        .store, .load, .add, .sub, .mul, .div, .@"and", .@"or" => utils.structs.sum_bit_size(Instruction.RegReg),
        .move => @as(usize, @bitSizeOf(Register)) + if (is_reg) @as(usize, @bitSizeOf(Register)) else @as(usize, @bitSizeOf(Word)),
    };

    return std.math.divCeil(usize, bit_size, @as(usize, 8)) catch unreachable;
}

test "BinaryInstruction byte sizes" {
    const testing = std.testing;
    const expectEqual = testing.expectEqual;

    var inst = BinaryInstruction{ .type = .not, .payload = .{ .reg = .R0 } };

    try expectEqual(@as(usize, 24), @bitSizeOf(BinaryInstruction));
    try expectEqual(@as(usize, 1), inst.byte_count());
    inst = .{ .type = .move, .payload = .{ .move = .{ .src = .{ .@"const" = 42 }, .is_reg = false, .dst = .R1 } } };
    try expectEqual(@as(usize, 3), inst.byte_count());
    inst = .{ .type = .add, .payload = .{ .reg_reg = .{ .src = .R0, .dst = .R1 } } };
    try expectEqual(@as(usize, 2), inst.byte_count());

    inst = .{ .type = .store, .payload = .{ .reg_reg = .{ .src = .R0, .dst = .R1 } } };
    try expectEqual(@as(usize, 2), inst.byte_count());
}

test "Instruction to BinaryInstruction" {
    const testing = std.testing;
    const expect = testing.expect;

    var inst = Instruction{ .not = .R0 };
    try expect(inst.pack().eql(BinaryInstruction{ .type = .not, .payload = .{ .reg = .R0 } }));

    inst = .{ .store = .{ .src = .R1, .dst = .R2 } };
    try expect(inst.pack().eql(BinaryInstruction{ .type = .store, .payload = .{ .reg_reg = .{ .src = .R1, .dst = .R2 } } }));

    inst = .{ .add = .{ .src = .R0, .dst = .R1 } };
    try expect(inst.pack().eql(BinaryInstruction{ .type = .add, .payload = .{ .reg_reg = .{ .src = .R0, .dst = .R1 } } }));
}
