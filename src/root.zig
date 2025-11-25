//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const bluetooth = @import("adapter.zig");

pub const Adapter = bluetooth.Adapter;
pub const DiscoverOptions = bluetooth.DiscoverOptions;
pub const InquiryResults = bluetooth.InquiryResults;
pub const DeviceList = bluetooth.DeviceList;
pub const Device = bluetooth.Device;
pub const Errors = bluetooth.Errors;

