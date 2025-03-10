const cpu = @import("cpu.zig");
const std = @import("std");

pub const InstructionType = enum(u4) {
    Add,
    Sub,
    Mul,
    Div,
    Inc,
    Dec,
    Signed,

    And,
    Or,
    Not,

    Move,
    Store,
    Load,

    Branch,
    BranchIfZero,

    /// stops execution (there are not interupts)
    Halt,
};

pub const Instruction = union(InstructionType) {
    pub const GeneralInst = struct {
        dst: cpu.Register,
        src: union(enum) {
            reg: cpu.Register,
            constant: cpu.Word,
        },

        fn to_packed(self: *const @This()) BinaryInstruction.GeneralInst {
            var tmp = BinaryInstruction.GeneralInst{
                .dst = self.dst,
                .is_reg = self.src == .reg,
                .src = undefined,
            };

            switch (self.src) {
                .reg => |r| tmp.src.reg = r,
                .constant => |c| tmp.src.constant = c,
            }

            return tmp;
        }
    };

    pub const MemoryInst = BinaryInstruction.MemoryInst;

    Add: GeneralInst,
    Sub: GeneralInst,
    Mul: GeneralInst,
    Div: GeneralInst,
    Inc: cpu.Register,
    Dec: cpu.Register,
    Signed,

    And: GeneralInst,
    Or: GeneralInst,
    Not: cpu.Register,

    Move: GeneralInst,
    Store: MemoryInst,
    Load: MemoryInst,

    Branch: cpu.Word,
    BranchIfZero: MemoryInst,

    /// stops execution (there are not interupts)
    Halt,

    inline fn is_gen_inst(self: @This()) bool {
        return switch (self) {
            .Add, .Sub, .Mul, .Div, .And, .Or, .Move => true,
            _ => false,
        };
    }

    pub fn to_bitary_instruction(self: @This()) BinaryInstruction {
        const activeTag = std.meta.activeTag;
        var inst: BinaryInstruction = undefined;
        inst.type = activeTag(self);

        switch (self) {
            .Add, .Sub, .Mul, .Div, .And, .Or, .Move => |gen| inst.data.gen = gen.to_packed(),
            .Inc, .Dec, .Not => |reg| inst.data.reg = reg,
            .Store, .Load, .BranchIfZero => |mem| inst.data.mem = mem,
            .Branch => |word| inst.data.word = word,
            .Signed, .Halt => inst.data = undefined,
        }

        return inst;
    }
};

pub const BinaryInstruction = packed struct {
    type: InstructionType,
    data: packed union {
        gen: GeneralInst,
        reg: cpu.Register,

        mem: MemoryInst,
        word: cpu.Word,
        none: void,
    },

    const Self = @This();
    /// max length without padding
    pub const MaxByteLen: usize = 3;

    /// requires the first byte to be readable
    pub fn byte_size(self: *const Self) usize {
        var bit_size: usize = @bitSizeOf(@TypeOf(self.type));
        bit_size += switch (self.type) {
            .Add, .Sub, .Mul, .Div, .And, .Or, .Move => self.data.gen.bit_size(),
            .Inc, .Dec, .Not => @bitSizeOf(cpu.Register),
            .Store, .Load, .BranchIfZero => @bitSizeOf(MemoryInst),
            .Branch => @bitSizeOf(cpu.Word),
            .Signed, .Halt => 0,
        };

        return std.math.divCeil(usize, bit_size, @as(usize, 8)) catch unreachable;
    }

    pub const GeneralInst = packed struct {
        dst: cpu.Register,
        is_reg: bool,
        src: packed union { reg: cpu.Register, constant: cpu.Word },

        pub fn bit_size(self: @This()) usize {
var size: usize = @bitSizeOf(@TypeOf(self.dst)) + @bitSizeOf(@TypeOf(self.is_reg));
            size += if (self.is_reg) @bitSizeOf(@TypeOf(self.src.reg)) else @bitSizeOf(@TypeOf(self.src.constant));
            return size;
        }
    };

    pub const MemoryInst = packed struct {
        reg: cpu.Register,
        mem_ptr: cpu.Word,
    };
};

test "BinaryInstruction byte sizes" {
    const testing = std.testing;
    const expectEqual = testing.expectEqual;

    var inst = BinaryInstruction { .type = .Not, .data = .{ .reg = .R0 } };

    try expectEqual(@as(usize, 24), @bitSizeOf(BinaryInstruction));
    try expectEqual(@as(usize, 1), inst.byte_size());
    inst = .{ .type = .Branch, .data = .{ .word = 42 } };
    try expectEqual(@as(usize, 3), inst.byte_size());
    inst = .{ .type = .Add, .data = .{ .gen = .{ .dst = .R0, .is_reg = true, .src = .{ .reg = .R1 } } } };
    try expectEqual(@as(usize, 2), inst.byte_size());
}
