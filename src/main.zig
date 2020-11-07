const std = @import("std");
const Connection = @import("x/Connection.zig");
const log = std.log;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    log.info("Starting juicebox...", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var connection = try Connection.init(&gpa.allocator);
    log.info("Initialized connection with X11 server: {}", .{connection.status});
    while (connection.status == .ok) {}
}
