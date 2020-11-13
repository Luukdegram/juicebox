const std = @import("std");
const Manager = @import("Manager.zig");
const log = std.log;
const events = @import("x11").events;
const errors = @import("x11").errors;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Starting juicebox...", .{});

    var manager = try Manager.init(&gpa.allocator);
    defer manager.deinit();

    log.info("Juicebox initialized", .{});

    var i: usize = 0;
    while (true) : (i += 1) {
        const response_byte = try manager.connection.reader().readByte();

        var bytes: [32]u8 = undefined;
        bytes[0] = response_byte;
        try manager.connection.reader().readNoEof(bytes[1..]);

        if (bytes[0] > 1 and bytes[0] < 35) {
            const event = events.Event.fromBytes(bytes);

            if (event != .motion_notify) {
                log.debug("EVENT: {}", .{@tagName(std.meta.activeTag(event))});
            }

            switch (event) {
                .button_press => |button| log.debug("Clicked button: {}", .{button.detail}),
                .key_press => |key| log.debug("Pressed key: {}", .{key.detail}),
                else => continue,
            }
        } else if (bytes[0] == 0) {
            // error occured
            const err = errors.Error.fromBytes(bytes);
            log.err("{} - seq: {}", .{ err.code, err.sequence });
            log.debug("Error details: {}", .{err});
        }
    }
}
