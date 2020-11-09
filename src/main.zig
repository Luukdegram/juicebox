const std = @import("std");
const Manager = @import("Manager.zig");
const log = std.log;
const events = @import("x11").events;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Starting juicebox...", .{});

    var manager = try Manager.init(&gpa.allocator);
    defer manager.deinit();

    log.info("Juicebox initialized", .{});

    while (true) {
        var bytes: [32]u8 = undefined;
        try manager.connection.handle.reader().readNoEof(&bytes);

        std.debug.print("Bytes: {}\n", .{bytes});
        // got an event!
        if (bytes[0] > 1 and bytes[0] < 35) {
            std.debug.print("Event: {}\n", .{@intToEnum(events.EventType, bytes[0])});
        }
    }
}
