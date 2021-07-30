//! The `Manager` is the heart of Juicebox. It manages all window creation,
//! event handling, and initialization of everything.
const std = @import("std");
const x = @import("x11");
const config = @import("config.zig").default_config;
const LayoutManager = @import("Layout.zig");
const log = std.log.scoped(.juicebox);
const Connection = x.Connection;
const Window = x.Window;
const Allocator = std.mem.Allocator;
const EventMask = x.events.Mask;
const input = x.input;
const events = x.events;
const errors = x.errors;

const Manager = @This();

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
/// Layout manager to manage all the windows and workspaces
layout_manager: *LayoutManager,

/// The mask we use for our root window
const root_event_mask = EventMask{
    .substructure_redirect = true,
    .substructure_notify = true,
    .structure_notify = true,
    .property_change = true,
};

/// Initializes a new Juicebox `Manager`. Connects with X11
/// and handle the root window setup
pub fn init(gpa: *Allocator) !*Manager {
    const manager = try gpa.create(Manager);
    errdefer gpa.destroy(manager);

    const conn = try gpa.create(Connection);
    errdefer gpa.destroy(conn);
    conn.* = try Connection.init(gpa);

    const screen = conn.screens[0];

    const lm = try gpa.create(LayoutManager);
    lm.* = LayoutManager.init(gpa, .{
        .width = screen.width_pixel,
        .height = screen.height_pixel,
    });
    errdefer gpa.destroy(lm);

    // create a Manager object and initialize the X11 connection
    manager.* = .{
        .gpa = gpa,
        .connection = conn,
        .root = undefined,
        .screen = undefined,
        .keysym_table = undefined,
        .layout_manager = lm,
    };

    // active screen as the first screen we find
    manager.screen = screen;

    // Set the root to the root of the first screen
    manager.root = Window{
        .handle = screen.root,
        .connection = conn,
    };

    //setup the root window to listen to events
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
    self.connection.deinit();
    self.keysym_table.deinit(self.gpa);
    self.layout_manager.deinit();
    self.gpa.destroy(self.connection);
    self.gpa.destroy(self.layout_manager);
    self.gpa.destroy(self);
}

/// Represents the type of response we have received
const ReplyType = enum(u8) {
    err,
    reply,
    _,
};

/// Runs the main event loop
pub fn run(self: *Manager) !void {
    while (true) {
        // all replies are 32 bit size
        var bytes: [32]u8 = undefined;
        try self.connection.reader().readNoEof(&bytes);

        try switch (bytes[0]) {
            0 => self.handleError(bytes),
            1 => unreachable, // replies should be handled at callsite
            2...34 => self.handleEvent(bytes),
            else => {}, // unhandled extensions
        };
    }
}

/// Handles all events received from X11
fn handleEvent(self: *Manager, buffer: [32]u8) !void {
    const event = events.Event.fromBytes(buffer);
    switch (event) {
        .key_press => |key| try self.onKeyPress(key),
        .map_request => |map| try self.onMap(map),
        .configure_request => |conf| try self.onConfigure(conf),
        .destroy_notify => |destroyable| try self.layout_manager.closeWindow(destroyable.window),
        .enter_notify => |entry| try self.onFocus(entry),
        else => {},
    }
}

/// Prints the error details from X11
/// TODO: Exit Juicebox as it's a developer error
fn handleError(self: *Manager, buffer: [32]u8) !void {
    _ = self;
    const err = errors.Error.fromBytes(buffer);
    log.err("ERROR: {s}", .{@tagName(err.code)});
}

/// Handles when a user presses a user-defined key binding
fn onKeyPress(self: *Manager, event: events.InputDeviceEvent) !void {
    inline for (config.bindings) |binding| {
        if (binding.symbol == self.keysym_table.keycodeToKeysym(event.detail) and
            binding.modifier.toInt() == event.state)
        {

            // found a key so execute its command
            switch (binding.action) {
                .cmd => |cmd| return runCmd(self.gpa, cmd),
                .function => |func| return self.callAction(func.action, func.arg),
            }
        }
    }
}

/// Asks the `LayoutManager` to map a new window and handle the tiling
fn onMap(self: *Manager, event: events.MapRequest) !void {
    const window = Window{ .connection = self.connection, .handle = event.window };
    try self.layout_manager.mapWindow(window);
}

/// Configures a new window to the requested configuration
/// Handling request notifies speeds up the speed of window creation
/// as X11 will wait for a reply before it sends a `MapRequest`
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
}

/// Checks to see if the event wasn't done on the root idx.
/// If not, focus the window by telling the layout manager to handle it.
fn onFocus(self: *Manager, event: events.PointerWindowEvent) !void {
    if (event.event == self.root.handle) return;
    try self.layout_manager.focusWindow(.{
        .handle = event.event,
        .connection = self.connection,
    });
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

    inline for (config.bindings) |binding| {
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

    process.spawn() catch log.err("Could not spawn cmd {s}", .{cmd[0]});
}

/// Calls an action defined in `actions.zig`
fn callAction(self: *Manager, action: anytype, arg: anytype) !void {
    const Fn = @typeInfo(@TypeOf(action)).Fn;
    const args = Fn.args;
    if (args.len == 1) try action(self);
    if (args.len == 2) try action(self, arg);
}
