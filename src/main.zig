const std = @import("std");
const x = @import("x11");
const Connection = x.Connection;
const Window = x.Window;
const log = std.log;
const events = x.events;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Starting juicebox...", .{});

    var connection = try Connection.init(&gpa.allocator);
    defer connection.disconnect();

    log.info("Initialized connection with X11 server: {}", .{connection.status});

    const window = try Window.create(&connection, connection.screens[0], .{
        .height = 500,
        .width = 500,
        .title = "Hello from Juicebox",
    }, &[1]x.protocol.ValueMask{.{
        .mask = x.protocol.Values.Window.back_pixel,
        .value = connection.screens[0].black_pixel,
    }});

    while (connection.status == .ok) {
        var bytes: [32]u8 = undefined;
        try connection.handle.reader().readNoEof(&bytes);

        // got an event!
        if (bytes[0] == 2) {
            std.debug.print("Event: {}\n", .{@intToEnum(events.EventType, bytes[0])});
        }
    }
}
