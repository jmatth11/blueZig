const std = @import("std");

const bluetooth = @cImport({
    @cInclude("bluetooth/bluetooth.h");
    @cInclude("bluetooth/hci.h");
    @cInclude("bluetooth/hci_lib.h");
});

const unknown_label: []const u8 = "[unknown]";

pub const Errors = error{
    adapter_init_failed,
    socket_init_failed,
    inquiry_failed,
};

pub const Device = struct {
    alloc: std.mem.Allocator,
    name: []const u8,
    addr: bluetooth.bdaddr_t,
    pub fn init(alloc: std.mem.Allocator, name: []const u8, addr: bluetooth.bdaddr_t) !Device {
        return .{
            .alloc = alloc,
            .name = try alloc.dupe(u8, name),
            .addr = addr,
        };
    }

    /// Populate the buf with the string version of the bluetooth address.
    pub fn addr_to_str(self: *const Device, buf: *[19]u8) void {
        _ = bluetooth.ba2str(&self.addr, &(buf.*));
    }

    pub fn deinit(self: *Device) void {
        self.alloc.free(self.name);
    }
};

pub const DeviceList = std.array_list.Managed(Device);

pub const InquiryResults = struct {
    alloc: std.mem.Allocator,
    devices: DeviceList,

    pub fn init(alloc: std.mem.Allocator) InquiryResults {
        return .{
            .alloc = alloc,
            .devices = .init(alloc),
        };
    }

    pub fn add(self: *InquiryResults, entry: Device) !void {
        try self.devices.append(entry);
    }

    pub fn deinit(self: *InquiryResults) void {
        for (self.devices.items) |*item| {
            item.*.deinit();
        }
        self.devices.deinit();
    }
};

pub const DiscoverOptions = struct {
    seconds: u64 = 8,
    max_responders: u64 = 255,
    flags: usize = bluetooth.IREQ_CACHE_FLUSH,
    lap: ?[]const u8 = null,
};

pub const Adapter = struct {
    alloc: std.mem.Allocator,
    device_id: c_int,
    socket: c_int,

    pub fn init(alloc: std.mem.Allocator) !Adapter {
        var result: Adapter = .{
            .alloc = alloc,
            .device_id = bluetooth.hci_get_route(null),
            .socket = undefined,
        };
        if (result.device_id < 0) {
            return Errors.adapter_init_failed;
        }
        result.socket = bluetooth.hci_open_dev(result.device_id);
        if (result.socket < 0) {
            return Errors.socket_init_failed;
        }
        return result;
    }

    pub fn discover(self: *const Adapter, options: DiscoverOptions) !InquiryResults {
        var results: InquiryResults = .init(self.alloc);
        errdefer results.deinit();
        var inquiries: []bluetooth.inquiry_info = try self.alloc.alloc(
            bluetooth.inquiry_info,
            options.max_responders,
        );
        defer self.alloc.free(inquiries);
        const num_responders: c_int = bluetooth.hci_inquiry(
            self.device_id,
            @intCast(options.seconds),
            @intCast(options.max_responders),
            null,
            @ptrCast(&inquiries.ptr),
            @intCast(options.flags),
        );
        if (num_responders < 0) {
            return Errors.inquiry_failed;
        }
        var i: usize = 0;
        var name: [248]u8 = @splat(0);
        while (i < num_responders) : (i += 1) {
            @memset(name[0..], 0);
            // read name from remote device.
            if (bluetooth.hci_read_remote_name(self.socket, // socket to bluetooth adapter
                &inquiries[i].bdaddr, // device address
                name.len, // length of name
                &name, // name to populate
                0 // timeout in milliseconds to try for the name.
            ) < 0) {
                @memcpy(name[0..unknown_label.len], unknown_label);
            }
            const end_op: ?usize = std.mem.indexOf(u8, name[0..], &.{0});
            var end = name.len;
            if (end_op) |val| {
                end = val;
            }
            const entry: Device = try .init(self.alloc, name[0..end], inquiries[i].bdaddr);
            try results.add(entry);
        }
        return results;
    }

    pub fn deinit(self: *Adapter) void {
        _ = std.c.close(self.socket);
    }
};
