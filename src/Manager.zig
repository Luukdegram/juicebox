const std = @import("std");
const x = @import("x11");
const config = @import("config.zig").default_config;
const log = std.log.scoped(.juicebox_manager);
const Connection = x.Connection;
const Window = x.Window;
const Allocator = std.mem.Allocator;
const EventMask = x.events.Mask;
const input = x.input;
const events = x.events;
const errors = x.errors;

const Manager = @This();

//! The `Manager` is the heart of Juicebox. It manages all window creation,
//! event handling, and initialization of everything.

/// Handle to our X11 connection. Required to communciate with the X11 server
connection: *Connection,
/// Our allocator, in case we need to allocate anything, such as the X11 setup info.
gpa: *Allocator,
/// Our root window, this is where all other windows will be rendered inside of.
root: Window,
/// The currently active screen. So we know which screen to
/// speak to when a user has multiple monitors.
screen: Connection.Screen,
/// The table of keysymbols which is used to convert to/from keycodes and keysyms
keysym_table: input.KeysymTable,

/// The mask we use for our root window
const root_event_mask = EventMask{
    .substructure_redirect = true,
    .substructure_notify = true,
    .button_press = true,
    .structure_notify = true,
    .pointer_motion = true,
    .property_change = true,
    .focus_change = true,
    .enter_window = true,
};

/// Initializes a new Juicebox `Manager`. Connects with X11
/// and handle the root window creation
pub fn init(gpa: *Allocator) !*Manager {
    const manager = try gpa.create(Manager);
    errdefer gpa.destroy(manager);

    const conn = try gpa.create(Connection);
    errdefer gpa.destroy(conn);
    conn.* = try Connection.init(gpa);

    // create a Manager object and initialize the X11 connection
    manager.* = .{
        .gpa = gpa,
        .connection = conn,
        .root = undefined,
        .screen = undefined,
        .keysym_table = undefined,
    };

    // active screen as the first screen we find
    manager.screen = conn.screens[0];

    // Set the root to the root of the first screen
    manager.root = Window{
        .handle = conn.screens[0].root,
        .connection = conn,
    };

    // setup the root window to listen to events
    try manager.root.changeAttributes(
        &[_]x.protocol.ValueMask{
            .{
                .mask = .event_mask,
                .value = root_event_mask.toInt(),
            },
        },
    );

    // Grabs all keys the user has defined
    try manager.grabKeys();

    return manager;
}

/// Closes the connection with X11 and frees all memory
pub fn deinit(self: *Manager) void {
    self.connection.disconnect();
    self.keysym_table.deinit(self.gpa);
    self.gpa.destroy(self.connection);
    self.gpa.destroy(self);
}

/// Runs the main event loop
pub fn run(self: *Manager) !void {
    while (true) {
        var bytes: [32]u8 = undefined;
        try self.connection.reader().readNoEof(&bytes);

        if (bytes[0] > 1 and bytes[0] < 35) {
            const event = events.Event.fromBytes(bytes);

            if (event != .motion_notify) {
                log.debug("EVENT: {}", .{@tagName(std.meta.activeTag(event))});
            }

            switch (event) {
                .button_press => |button| log.debug("Clicked button: {}", .{button.detail}),
                .key_press => |key| try self.onKeyPress(key),
                .configure_request => |conf| try self.onConfigure(conf),
                .map_request => |map| try self.onMap(map),
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

/// Handles when a user presses a user-defined key binding
fn onKeyPress(self: *Manager, event: events.InputDeviceEvent) !void {
    for (config.bindings) |binding| {
        if (binding.symbol != self.keysym_table.keycodeToKeysym(event.detail)) continue;

        // found a key so execute its command
        switch (binding.action) {
            .cmd => |cmd| try runCmd(self.gpa, cmd),
            .function => |func| {},
        }
        return;
    }
}

/// Configures a new window
fn onConfigure(self: *Manager, event: events.ConfigureRequest) !void {
    const window = Window{
        .handle = event.window,
        .connection = self.connection,
    };
    const mask = @bitCast(x.protocol.WindowConfigMask, event.mask);

    const window_config = x.protocol.WindowChanges{
        .x = event.x,
        .y = event.y,
        .width = event.width,
        .height = event.height,
        .border_width = event.border_width,
        .sibling = event.sibling,
        .stack_mode = event.stack_mode,
    };

    try window.configure(mask, window_config);
    log.debug("Configured window id: {d}", .{event.window});
}

/// Maps a new window
fn onMap(self: *Manager, event: events.MapRequest) !void {
    try Window.map(self.connection, event.window);
    log.debug("Mapped window id: {d}", .{event.window});
}

/// Grabs the mouse buttons the user has defined
/// TODO: Create user configuration and make the manager aware of it
fn grabUserButtons(self: Manager) !void {
    try input.grabButton(self.connection, .{
        .confine_to = self.root,
        .grab_window = self.root,
        .event_mask = .{ .button_press = true, .button_release = true },
        .button = 0, // grab any key
        .modifiers = input.Modifiers.any,
    });
}

/// Grab the keys the user has defined
fn grabKeys(self: *Manager) !void {
    // Ungrab all keys
    try input.ungrabKey(self.connection, 0, self.root, input.Modifiers.any);

    // Get all keysyms
    self.keysym_table = try input.KeysymTable.init(self.connection);

    for (config.bindings) |binding| {
        try input.grabKey(
            self.connection,
            .{
                .grab_window = self.root,
                .modifiers = binding.modifier,
                .key_code = self.keysym_table.keysymToKeycode(binding.symbol),
            },
        );
    }
}

/// Runs a shell cmd
fn runCmd(gpa: *Allocator, cmd: []const []const u8) !void {
    if (cmd.len == 0) return;

    var process = try std.ChildProcess.init(cmd, gpa);
    defer process.deinit();

    process.spawn() catch |err| log.err("Could not spawn cmd {}", .{cmd[0]});
}
