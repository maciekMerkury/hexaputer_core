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

    inc,
    dec,
    not,
    /// sets the reg to 0
    zero,

    store,
    load,
    /// normal branch is just load into isp
    branchIfZero,

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

    inc: Register,
    dec: Register,
    not: Register,
    zero: Register,

    store: Mem,
    load: Mem,
    branchIfZero: Mem,

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

    pub const MaxByteLen: usize = 3;

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
                .halt, .signed => undefined,
                .inc, .dec, .not, .zero => |reg| .{ .reg = reg },
                .store, .load, .branchIfZero => |mem| .{ .mem = utils.copy(mem, @FieldType(Payload, "mem")) },
                .add, .sub, .mul, .div, .@"and", .@"or" => |regreg| .{ .reg_reg = utils.copy(regreg, @FieldType(Payload, "reg_reg")) },
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
                    writer.print("{}", .{value.src.reg});
                } else {
                    writer.print("{}", .{value.src.@"const"});
                }

                try writer.print(", .dst = {}}}", .{value.dst});
            }
        },

        reg: Register,
        mem: utils.pack_struct(Instruction.Mem),
        reg_reg: utils.pack_struct(Instruction.RegReg),
        nothing: void,
    };

    /// returns the byte len of the instruction, represented by the first byte
    pub inline fn byte_count(byte: u8) usize {
        const Tmp = packed struct(u8) {
            type: InstructionType,

            /// only valid if type == .move
            is_reg: bool,
            _: u3,
        };

        const inst: Tmp = @bitCast(byte);

        return byte_size(inst.type, inst.type == .move and inst.is_reg);
    }

    pub fn eql(self: @This(), other: @This()) bool {
        const len = Instruction.MaxByteLen;

        var bytes: [2][len]u8 = .{.{0} ** len} ** 2;
        bytes[0] = @bitCast(self);
        bytes[1] = @bitCast(other);
        const len_self = byte_count(bytes[0][0]);
        const len_other = byte_count(bytes[1][0]);

        return std.mem.eql(u8, bytes[0][0..len_self], bytes[1][0..len_other]);
    }

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("BinaryInstruction{{ .type = {}, .data = ", .{value.type});
        try switch (value.type) {
            .halt, .signed => writer.print("{}", .{value.data.nothing}),
            .inc, .dec, .not, .zero => writer.print("{}", .{value.data.reg}),
            .store, .load, .branchIfZero => writer.print("{}", .{value.data.mem}),
            .add, .sub, .mul, .div, .@"and", .@"or" => writer.print("{}", .{value.data.reg_reg}),
            .move => writer.print("{}", .{value.data.move}),
        };
        return writer.print(" }}", .{});
    }
};

fn byte_size(t: InstructionType, is_reg: bool) usize {
    var bit_size: usize = @bitSizeOf(InstructionType);
    bit_size += switch (t) {
        .halt, .signed => 0,
        .inc, .dec, .not, .zero => @bitSizeOf(Register),
        .store, .load, .branchIfZero => utils.sum_bit_size(Instruction.Mem),
        .add, .sub, .mul, .div, .@"and", .@"or" => utils.sum_bit_size(Instruction.RegReg),
        .move => @as(usize, @bitSizeOf(Register)) + if (is_reg) @as(usize, @bitSizeOf(Register)) else @as(usize, @bitSizeOf(Word)),
    };

    return std.math.divCeil(usize, bit_size, @as(usize, 8)) catch unreachable;
}
