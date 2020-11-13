const Connection = @import("Connection.zig");
const Window = @import("Window.zig");
const EventMask = @import("events.zig").Mask;
usingnamespace @import("protocol.zig");

pub const Modifiers = packed struct {
    /// Shift keys
    shift: bool = false,
    /// Capslock key
    lock: bool = false,
    /// Control keys
    control: bool = false,
    /// Alt L & R + Meta L
    @"1": bool = false,
    /// Num lock
    @"2": bool = false,
    /// Empty by default
    @"3": bool = false,
    /// Super keys L & R and Hyper L
    @"4": bool = false,
    /// ISO_Level3_Shift and Mode Switch key
    @"5": bool = false,

    padding: u7 = 0,
    any_bit: bool = false,

    pub const any: @This() = .{ .any_bit = true };

    pub fn toInt(self: @This()) u16 {
        return @bitCast(u16, self);
    }

    pub inline fn set(self: *@This(), comptime field: []const u8) void {
        @field(self, field) = true;
    }

    pub inline fn clear(self: *@This(), comptime field: []const u8) void {
        @field(self, field) = false;
    }
};

/// Options to set when grabbing a button
pub const GrabButtonOptions = struct {
    owner_events: bool = false,
    /// which pointer events to grab
    event_mask: EventMask = .{},
    /// How events are triggered. Async by default
    pointer_mode: GrabMode = .@"async",
    /// How events are triggered. Async by default
    keyboard_mode: GrabMode = .@"async",
    /// The window that owns the grab
    grab_window: Window,
    /// The window where the events are sent to
    confine_to: Window,
    /// Which cursor to show, 0 (none) by default
    cursor: Types.Cursor = 0,
    /// Which button to grab
    button: u8,
    /// The modifier required to grab a button
    modifiers: Modifiers,
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
        .grab_window = options.grab_window.handle,
        .event_mask = @truncate(u16, options.event_mask.toInt()),
        .pointer_mode = @enumToInt(options.pointer_mode),
        .keyboard_mode = @enumToInt(options.keyboard_mode),
        .confine_to = options.confine_to.handle,
        .cursor = options.cursor,
        .button = options.button,
        .modifiers = options.modifiers.toInt(),
    });
}

/// Ungrabs a button and its modifiers. Use 0 for `button` to ungrab all buttons
pub fn ungrabButton(conn: *Connection, button: u8, window: Window, modifiers: Modifiers) !void {
    try conn.send(UngrabButtonRequest{
        .button = button,
        .window = window.handle,
        .modifiers = modifiers.toInt(),
    });
}

/// The options to grab a specific key
pub const GrabKeyOptions = struct {
    /// Is owner of events
    owner_events: bool = false,
    /// Window that will recieve events for those keys
    grab_window: Window,
    /// Which modifier keys to be used
    modifiers: Modifiers,
    /// The actual key to grab
    key_code: Types.Keycode,
    /// How the pointer events are triggered
    pointer_mode: GrabMode.@"async",
    /// How the keyboard events are triggered
    keyboard_mode: GrabMode.@"async",
};

/// Grabs a key with optional modifiers for the given window
pub fn grabKey(conn: *Connection, options: GrabKeyOptions) !void {
    try conn.send(GrabKeyRequest{
        .owner_events = @boolToInt(options.owner_events),
        .grab_window = options.grab_window.handle,
        .modifiers = options.modifiers.toInt(),
        .key = options.key_code,
        .pointer_mode = options.pointer_mode,
        .keyboard_mode = options.keyboard_mode,
    });
}

/// Ungrabs the key and its modifiers for the specified window
pub fn ungrabKey(conn: *Connection, key: Types.Keycode, window: Window, modifiers: Modifiers) !void {
    try conn.send(UngrabKeyRequest{
        .key_code = key,
        .window = window.handle,
        .modifiers = modifiers.toInt(),
    });
}

/// Converts a keysym to a keycode
pub fn keysymToKeycode(conn: *Connection, keysym: Types.Keysym) !Types.keycode {}

/// Converts a keycode to a keysym
pub fn keycodeToKeysym(conn: *Connection, keycode: Types.Keycode) !Types.Keysym {}
