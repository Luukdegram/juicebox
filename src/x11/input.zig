const Connection = @import("Connection.zig");

usingnamespace @import("protocol.zig");

/// Contains the mask of the modifier keys
pub const ModMask = enum(u16) {
    /// shift keys
    shift = 1,
    /// Capslock key
    lock = 2,
    /// Ctrl keys
    control = 4,
    /// Alt L & R + Meta L
    @"1" = 8,
    /// Num lock
    @"2" = 16,
    /// Empty by default
    @"3" = 32,
    /// Super keys L & R and Hyper L
    @"4" = 64,
    /// ISO_Level3_Shift and Mode Switch key
    @"5" = 128,
    /// Any of the modifier keys
    any = 32768,
};

/// Options to set when grabbing a button
pub const GrabButtonOptions = struct {
    owner_events: bool = false,
    /// which events to grab
    event_mask: u16 = 0,
    /// How events are triggered. Async by default
    pointer_mode: GrabMode = .@"async",
    /// How events are triggered. Async by default
    keyboard_mode: GrabMode = .@"async",
    /// The window that owns the grab
    grab_window: Types.Window,
    /// The window where the events are sent to
    confine_to: Types.Window,
    /// Which cursor to show, 0 (none) by default
    cursor: Types.Cursor = 0,
    /// Which button to grab
    button: u8,
    /// The modifier required to grab a button
    modifiers: ModMask,
};

/// Whether the grab mode should be sync -or asynchronous
pub const GrabMode = enum(u8) {
    sync = 0,
    @"async" = 1,
};

/// Grabs a button and binds it to specific windows
pub fn grabButton(conn: *Connection, options: GrabButtonOptions) !void {
    try conn.send(GrabButtonRequest{
        .owner_events = @boolToInt(options.owner_events),
        .grab_window = options.grab_window,
        .event_mask = options.event_mask,
        .pointer_mode = @enumToInt(options.pointer_mode),
        .keyboard_mode = @enumToInt(options.keyboard_mode),
        .confine_to = options.confine_to,
        .cursor = options.cursor,
        .button = options.button,
        .modifiers = @enumToInt(options.modifiers),
    });
}

/// Ungrabs a button and its modifiers. Use 0 for `button` to ungrab all buttons
pub fn ungrabButton(conn: *Connection, button: u8, window: @import("Window.zig"), modifiers: ModMask) !void {
    try conn.send(UngrabButtonRequest{
        .button = button,
        .window = window.handle,
        .modifiers = @enumToInt(modifiers),
    });
}
