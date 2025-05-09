const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");

const Instruction = @import("instruction.zig").Instruction;
const BinaryInstruction = @import("instruction.zig").BinaryInstruction;

pub const Word = u16;

pub const Endianness = std.builtin.Endian.little;

pub const Register = enum(u3) {
    R0,
    R1,
    R2,
    R3,
    R4,
    R5,

    /// instruction pointer
    ISP,
    /// stack pointer
    SP,
};

pub const Registers = struct {
    const register_count = @typeInfo(Register).@"enum".fields.len;
    _regs: [register_count]Word = .{0} ** register_count,

    pub inline fn get(self: *@This(), reg: Register) *Word {
        return &self._regs[@intFromEnum(reg)];
    }
};

pub const CPU = struct {
    regs: Registers = .{},
    mem: []u8 = undefined,
    addressing: AddressingMode = .physical,
    next_signed: bool = false,

    const AddressingMode = enum {
        physical,
        mmio,

        pub inline fn swap(self: *@This()) void {
            self.* = if (self.* == .physical) .mmio else .physical;
        }
    };

    pub fn init(self: *@This(), mem_size: Word, alloc: *Allocator) !void {
        self.mem = try alloc.alloc(u8, mem_size);
        @memset(self.mem, 0);
        self.reset_regs();
    }

    pub fn reset_regs(self: *@This()) void {
        self.regs = .{};
        self.regs.get(.SP).* = @as(Word, @intCast(self.mem.len)) - 1;
    }

    pub fn deinit(self: *@This(), alloc: *Allocator) void {
        alloc.free(self.mem);
    }

    pub fn process_next_inst(self: *@This()) !bool {
        const inst = try self.next_inst();

        switch (inst.type) {
            .halt => return false,
            .signed => self.next_signed = true,
            .address_switch => {
                self.addressing.swap();
                @panic("not implemented");
            },

            .inc, .dec => {
                const reg = self.regs.get(inst.payload.reg);

                reg.* = if (inst.type == .inc) @addWithOverflow(reg.*, 1).@"0" else @subWithOverflow(reg.*, 1).@"0";
            },

            .not => {
                const reg = self.regs.get(inst.payload.reg);
                reg.* = ~reg.*;
            },

            .branchIfZero => {
                const mem = inst.payload.mem;

                if (self.regs.get(mem.reg).* == 0) {
                    self.regs.get(.ISP).* = mem.ptr;
                }
            },

            .store => {
                const reg = inst.payload.reg_reg;

                const dst_ptr = self.regs.get(reg.dst).*;

                if (@as(usize, dst_ptr) + 1 >= self.mem.len) {
                    return error.OutOfBounds;
                }

                var bytes: [@sizeOf(Word)]u8 = undefined;
                std.mem.writeInt(Word, &bytes, self.regs.get(reg.src).*, Endianness);

                @memcpy(self.mem[dst_ptr .. dst_ptr + @sizeOf(Word)], &bytes);
            },

            .load => {
                const reg = inst.payload.reg_reg;

                const src_ptr = self.regs.get(reg.src).*;

                if (@as(usize, src_ptr) + 1 >= self.mem.len) {
                    return error.OutOfBounds;
                }

                var bytes: [@sizeOf(Word)]u8 = undefined;
                @memcpy(&bytes, self.mem[src_ptr .. src_ptr + @sizeOf(Word)]);

                self.regs.get(reg.dst).* = std.mem.readInt(Word, &bytes, Endianness);
            },

            .add, .sub, .mul, .div, .@"and", .@"or" => {
                const reg = inst.payload.reg_reg;

                const src = self.regs.get(reg.src).*;
                const dst = self.regs.get(reg.dst);

                switch (inst.type) {
                    .add => dst.* = @addWithOverflow(dst.*, src).@"0",
                    .sub => dst.* = @addWithOverflow(dst.*, src).@"0",
                    .mul => dst.* = @addWithOverflow(dst.*, src).@"0",
                    .div => {
                        if (src == 0) {
                            return error.DivByZero;
                        }
                        dst.* /= src;
                    },
                    .@"and" => dst.* &= src,
                    .@"or" => dst.* |= src,

                    else => unreachable,
                }
            },

            .move => {
                const move = inst.payload.move;
                const dst = self.regs.get(move.dst);

                dst.* = if (move.is_reg) self.regs.get(move.src.reg).* else move.src.@"const";
            },
        }

        return true;
    }

    /// moves isp to after the inst
    fn next_inst(self: *@This()) !BinaryInstruction {
        const isp = self.regs.get(.ISP);
        const buf: u8 = (try utils.slices.get(self.mem, isp.*)).*;

        const len = BinaryInstruction.bytes_left(buf) + 1;
        if (isp.* + len > self.mem.len) {
            return error.OutOfBounds;
        }
        defer isp.* += @intCast(len);

        var inst_buf: [Instruction.MaxByteLen]u8 = undefined;
        @memcpy(inst_buf[0..len], self.mem[isp.*..][0..len]);
        return @bitCast(inst_buf);
    }

    /// moves isp to after the inst
    fn add_inst(self: *@This(), inst: Instruction) !void {
        const tmp: [Instruction.MaxByteLen]u8 = @bitCast(inst.pack());
        const len = inst.byte_count();
        const isp = self.regs.get(.ISP);

        if (isp.* + len > self.mem.len) {
            return error.OutOfBounds;
        }

        @memcpy(self.mem[isp.*..][0..len], tmp[0..len]);
        isp.* += @intCast(len);
    }

    /// also resets the reg state
    pub fn push_program(self: *@This(), program: []const Instruction) !Word {
        if (program[program.len - 1] != .halt)
            return error.NoHalt;

        for (program) |inst| {
            try self.add_inst(inst);
        }

        const isp = self.regs.get(.ISP).*;
        self.regs = .{};

        return isp;
    }

    pub fn get_remaining_program(self: *@This(), alloc: std.mem.Allocator) !std.ArrayListUnmanaged(BinaryInstruction) {
        const isp = self.regs.get(.ISP).*;
        defer self.regs.get(.ISP).* = isp;

        var list = try std.ArrayListUnmanaged(BinaryInstruction).initCapacity(alloc, 1);
        errdefer list.deinit(alloc);

        var inst = try self.next_inst();
        while (true) : (inst = try self.next_inst()) {
            try list.append(alloc, inst);

            if (inst.type == .halt) break;
        }

        return list;
    }
};

test "one inst next_inst" {
    const testing = std.testing;
    var alloc = testing.allocator;
    var cpu = CPU{};
    try cpu.init(1, &alloc);
    defer cpu.deinit(&alloc);

    const inst: Instruction = .halt;
    try cpu.add_inst(inst);
    cpu.regs = .{};

    const res = try cpu.next_inst();
    try testing.expect(res.type == .halt);
}

test "more complex next_inst" {
    const testing = std.testing;
    var alloc = testing.allocator;
    var cpu = CPU{};
    try cpu.init(32, &alloc);
    defer cpu.deinit(&alloc);

    const insts: [3]Instruction = .{
        .{ .move = .{ .src = .{ .@"const" = 42 }, .dst = .R0 } },
        .{ .inc = .R1 },
        .{ .add = .{ .src = .R1, .dst = .R0 } },
    };

    for (insts) |inst| {
        try cpu.add_inst(inst);
    }

    cpu.reset_regs();

    for (insts) |inst| {
        try testing.expect(inst.pack().eql(try cpu.next_inst()));
    }
}

test "simple halt" {
    const testing = std.testing;
    var alloc = testing.allocator;

    var cpu = CPU{};
    try cpu.init(32, &alloc);
    defer cpu.deinit(&alloc);

    const inst = Instruction.halt;
    try cpu.add_inst(inst);
    cpu.reset_regs();

    try testing.expect(try cpu.process_next_inst() == false);
}

test "add 2 regs" {
    const testing = std.testing;
    var alloc = testing.allocator;

    var cpu = CPU{};
    try cpu.init(32, &alloc);
    defer cpu.deinit(&alloc);

    const program = [4]Instruction{
        .{ .move = .{ .dst = .R0, .src = .{ .@"const" = 42 } } },
        .{ .move = .{ .dst = .R1, .src = .{ .@"const" = 69 } } },
        .{ .add = .{ .src = .R1, .dst = .R0 } },
        .halt,
    };

    const isp = try cpu.push_program(&program);

    while (try cpu.process_next_inst()) {}

    try testing.expectEqual(isp, cpu.regs.get(.ISP).*);
    try testing.expectEqual(42 + 69, cpu.regs.get(.R0).*);
}
