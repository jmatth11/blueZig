const std = @import("std");
const bluezig = @import("bluezig");

pub fn main() !void {
    var adapter: bluezig.Adapter = try .init(std.heap.smp_allocator);
    defer adapter.deinit();

    var results = try adapter.discover(.{});
    defer results.deinit();

    for (results.devices.items) |device| {
        var addr: [19]u8 = @splat(0);
        device.addr_to_str(&addr);
        std.debug.print("{s}, {s}\n", .{device.name, addr});
    }
}
