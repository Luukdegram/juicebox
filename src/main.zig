const std = @import("std");
const x = @import("x11/x11.zig");
const Connection = x.Connection;
const Window = x.Window;
const log = std.log;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    log.info("Starting juicebox...", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var connection = try Connection.init(&gpa.allocator);
    defer connection.disconnect();
    log.info("Initialized connection with X11 server: {}", .{connection.status});
    const window = try Window.create(&connection, connection.screens[0], .{
        .height = 500,
        .width = 500,
        .title = "Hello from Juicebox",
    });
    while (connection.status == .ok) {}
}
