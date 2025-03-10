const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");

pub const Instruction = @import("instruction.zig").Instruction;

pub const Word = u16;

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
    const register_count = @typeInfo(Register).Enum.fields.len;
    _regs: [register_count]Word = .{0} ** register_count,

    pub inline fn get(self: *@This(), reg: Register) *Word {
        return &self._regs[@intFromEnum(reg)];
    }
};

pub const CPU = struct {
    regs: Registers = .{},
    mem: []u8 = undefined,

    pub fn init(self: *@This(), mem_size: usize, alloc: *Allocator) !void {
        self.mem = try alloc.alloc(u8, mem_size);
        @memset(self.mem, 0);
    }

    pub fn deinit(self: *@This(), alloc: *Allocator) void {
        alloc.free(self.mem);
    }

    /// moves isp to after the inst
    fn next_inst(self: *@This()) !Instruction {
        const isp = self.regs.get(.ISP);
        var buf: u8 align(@alignOf(Instruction)) = (try utils.get(self.mem, isp.*)).*;

        const len = Instruction.byte_size(@ptrCast(&buf));
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
        const tmp: [Instruction.MaxByteLen]u8 = @bitCast(inst);
        const len = inst.byte_size();
        const isp = self.regs.get(.ISP);

        if (isp.* + len > self.mem.len) {
            return error.OutOfBounds;
        }

        @memcpy(self.mem[isp.*..][0..len], tmp[0..len]);
        isp.* += @intCast(len);
    }
};

test "one inst next_inst" {
    const testing = std.testing;
    var alloc = testing.allocator;
    var cpu = CPU{};
    try cpu.init(1, &alloc);
    defer cpu.deinit(&alloc);

    const inst: Instruction = .{ .type = .Halt, .data = undefined };
    try cpu.add_inst(inst);
    cpu.regs = .{};

    const res = try cpu.next_inst();
    try testing.expect(res.type == .Halt);
}

fn are_insts_equal(a: Instruction, b: Instruction) bool {
    const bufa: [3]u8 = @bitCast(a);
    const bufb: [3]u8 = @bitCast(b);

    return std.mem.eql(u8, bufa[0..a.byte_size()], bufb[0..b.byte_size()]);
}

test "more complex next_inst" {
    const testing = std.testing;
    var alloc = testing.allocator;
    var cpu = CPU{};
    try cpu.init(32, &alloc);
    defer cpu.deinit(&alloc);

    const insts: [2]Instruction = .{
        .{ .type = .Move, .data = .{ .gen = .{ .dst = .R0, .is_reg = false, .src = .{ .constant = 42 } } } },
        .{ .type = .Inc, .data = .{ .reg = .R1 } },
        // .{ .type = .Add, .data = .{ .gen = .{ .src = .{ .reg = .R1 }, .is_reg = false, .dst = .R0 } } },
    };

    for (insts) |inst| {
        try cpu.add_inst(inst);
    }

    cpu.regs = .{};

    for (insts) |inst| {
        try testing.expect(are_insts_equal(try cpu.next_inst(), inst));
    }
}
