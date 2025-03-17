const cpu = @import("cpu.zig");
const std = @import("std");
const utils = @import("utils.zig");
const shit = @import("overcomplicated.zig");

pub const InstructionType = enum(u4) {
    /// stops execution (there are not interupts)
    Halt = 0,
    /// The next maths op will be signed
    Signed,

    Inc = 2,
    Dec,
    Not,

    Store = 5,
    Load,
    /// normal branch is just Load into ISP
    BranchIfZero,

    Add = 8,
    Sub,
    Mul,
    Div,
    And,
    Or,
    Move,
};

pub const Instruction = union(InstructionType) {
    pub const GeneralInst = struct {
        dst: cpu.Register,
        src: union(enum) {
            reg: cpu.Register,
            constant: cpu.Word,
        },

        fn to_packed(self: *const @This()) BinaryInstruction.GeneralInst {
            return BinaryInstruction.GeneralInst{ .dst = self.dst, .is_reg = self.src == .reg, .src = switch (self.src) {
                .reg => |r| .{ .reg = r },
                .constant => |c| .{ .constant = c },
            } };
        }
    };
    pub const MemoryInst = BinaryInstruction.MemoryInst;
    pub const MaxByteLen = BinaryInstruction.MaxByteLen;
    Halt,
    Signed,

    Inc: cpu.Register,
    Dec: cpu.Register,
    Not: cpu.Register,

    Store: MemoryInst,
    Load: MemoryInst,
    BranchIfZero: MemoryInst,

    Add: GeneralInst,
    Sub: GeneralInst,
    Mul: GeneralInst,
    Div: GeneralInst,
    And: GeneralInst,
    Or: GeneralInst,
    Move: GeneralInst,

    inline fn is_gen_inst(self: @This()) bool {
        return self >= InstructionType.Add;
    }

    pub fn to_binary_instruction(self: @This()) BinaryInstruction {
        const activeTag = std.meta.activeTag;
        var inst: BinaryInstruction = undefined;
        inst.type = activeTag(self);

        inst.data = switch (self) {
            .Halt, .Signed => undefined,
            .Inc, .Dec, .Not => |reg| .{ .reg = reg },
            .Store, .Load, .BranchIfZero => |mem| .{ .mem = mem },
            .Add, .Sub, .Mul, .Div, .And, .Or, .Move => |gen| .{ .gen = gen.to_packed() },
        };
        std.debug.print("{}\n", .{inst});

        return inst;
    }
};

pub const BinaryInstruction = packed struct {
    type: InstructionType,
    data: Data,

    const Data = packed union {
        gen: GeneralInst,
        reg: cpu.Register,

        mem: MemoryInst,
        none: void,
    };

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
            .Signed, .Halt => 0,
        };

        return std.math.divCeil(usize, bit_size, @as(usize, 8)) catch unreachable;
    }

    pub fn eql(self: Self, other: Self) bool {
        std.debug.print("self: {}, other: {}\n", .{ self, other });
        var a: [3]u8 = .{0} ** 3;
        a = @bitCast(self);
        var b: [3]u8 = .{0} ** 3;
        b = @bitCast(self);
        std.debug.print("a: {any}, b: {any}\n", .{ a, b });

        return std.mem.eql(u8, a[0..self.byte_size()], b[0..other.byte_size()]);
    }

    pub fn format(value: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("BinaryInstruction{{ .type = {}, .data = ", .{value.type});
        try switch (value.type) {
            .Halt, .Signed => writer.print("{}", .{value.data.none}),
            .Inc, .Dec, .Not => writer.print("{}", .{value.data.reg}),
            .Store, .Load, .BranchIfZero => writer.print("{}", .{value.data.mem}),
            .Add, .Sub, .Mul, .Div, .And, .Or, .Move => writer.print("{}", .{value.data.gen}),
        };
        return writer.print(" }}", .{});
    }
};

test "BinaryInstruction byte sizes" {
    const testing = std.testing;
    const expectEqual = testing.expectEqual;

    var inst = BinaryInstruction{ .type = .Not, .data = .{ .reg = .R0 } };

    try expectEqual(@as(usize, 24), @bitSizeOf(BinaryInstruction));
    try expectEqual(@as(usize, 1), inst.byte_size());
    inst = .{ .type = .Store, .data = .{ .mem = .{ .reg = .ISP, .mem_ptr = 42 } } };
    try expectEqual(@as(usize, 3), inst.byte_size());
    inst = .{ .type = .Add, .data = .{ .gen = .{ .dst = .R0, .is_reg = true, .src = .{ .reg = .R1 } } } };
    try expectEqual(@as(usize, 2), inst.byte_size());
}

test "converting Instruction to BinaryInstruction" {
    const testing = std.testing;
    const expect = testing.expect;

    var inst = Instruction{ .Not = .R0 };
    try expect(BinaryInstruction.eql(inst.to_binary_instruction(), BinaryInstruction{ .type = .Not, .data = .{ .reg = .R0 } }));

    inst = .{ .Store = .{ .reg = .ISP, .mem_ptr = 42 } };
    try expect(BinaryInstruction.eql(inst.to_binary_instruction(), BinaryInstruction{ .type = .Store, .data = .{ .mem = .{ .reg = .ISP, .mem_ptr = 42 } } }));

    inst = .{ .Add = .{ .dst = .R0, .src = .{ .reg = .R1 } } };
    try expect(BinaryInstruction.eql(inst.to_binary_instruction(), BinaryInstruction{ .type = .Add, .data = .{ .gen = .{ .dst = .R0, .is_reg = true, .src = .{ .reg = .R1 } } } }));
}
