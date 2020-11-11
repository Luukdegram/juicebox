const std = @import("std");
const x = @import("x11");
const Connection = x.Connection;
const Window = x.Window;
const Allocator = std.mem.Allocator;
const Values = x.protocol.Values;
const EventMask = x.events.Mask;
const input = x.input;

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

/// The mask we use for our root window
const root_event_mask = EventMask.getMask(&[_]EventMask{
    .substructure_redirect,
    .substructure_notify,
    .button_press,
    .structure_notify,
    .pointer_motion,
    .property_change,
    .focus_change,
    .enter_window,
});

/// Initializes a new Juicebox `Manager`. Connects with X11
/// and handle the root window creation
pub fn init(gpa: *Allocator) !*Manager {
    const manager = try gpa.create(Manager);
    errdefer gpa.destroy(manager);

    const conn = try gpa.create(Connection);
    conn.* = try Connection.init(gpa);

    // create a Manager object and initialize the X11 connection
    manager.* = .{
        .gpa = gpa,
        .connection = conn,
        .root = undefined,
        .screen = undefined,
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
                .mask = Values.Window.event_mask,
                .value = root_event_mask,
            },
        },
    );

    return manager;
}

/// Closes the connection with X11 and frees all memory
pub fn deinit(self: *Manager) void {
    self.connection.disconnect();
    self.gpa.destroy(self.connection);
    self.gpa.destroy(self);
}

/// Grabs the buttons the user has defined
/// TODO: Create user configuration and make the manager aware of it
fn grabUserButtons(self: Manager) !void {
    try input.grabButton(self.connection, .{
        .confine_to = self.root.handle,
        .grab_window = self.root.handle,
        .event_mask = @enumToInt(EventMask.button_press) | @enumToInt(EventMask.button_release),
        .button = 0, // grab any key
        .modifiers = .any, // any modifier
    });
}
