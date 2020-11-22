const std = @import("std");
const x = @import("x11");
const config = @import("config.zig").default_config;
const Workspace = @import("Workspace.zig");
const Window = x.Window;
const Allocator = std.mem.Allocator;
const events = x.events;
const log = std.log.scoped(.juicebox_layout);

const LayoutManager = @This();

//! This contains the layour manager. It is being called by the
//! Manager whenever a new window is created/updated/removed to ensure
//! all windows align with the selected layout rules.

/// Array of type `Workspace`
const Workspaces = [config.workspaces]Workspace;

/// Default mask when a new window is created
const window_event_mask = x.events.Mask{
    .enter_window = true,
    .focus_change = true,
};

/// The list of workspaces
workspaces: Workspaces,
/// The currently active workspace being displayed on the monitor
current: usize,
/// An allocator, used to add new Windows to a workspace and manage
/// the memory of the workspaces
gpa: *Allocator,
/// Screen dimensions
size: Size,

/// Screen dimensions
const Size = struct {
    width: u16,
    height: u16,
};

/// Initializes a new instance of `LayoutManager` and initializes all workspaces
pub fn init(gpa: *Allocator, size: Size) LayoutManager {
    var self = LayoutManager{
        .workspaces = undefined,
        .current = 0,
        .gpa = gpa,
        .size = size,
    };

    for (self.workspaces) |*ws, i| ws.* = Workspace.init(i);

    return self;
}

/// Frees the resources of the `LayoutManager`
pub fn deinit(self: *LayoutManager) void {
    for (self.workspaces) |ws| ws.deinit(self.gpa);
    self.* = undefined;
}

/// Returns the active `Workspace`
pub fn active(self: *LayoutManager) *Workspace {
    return &self.workspaces[self.current];
}

/// Attempts to find the Workspace of the given `Window` `handle`
/// Returns `null` if the window does not exist in any of the workspaces
fn find(self: *LayoutManager, handle: x.protocol.Types.Window) ?*Workspace {
    for (self.workspaces) |*ws| {
        if (ws.contains(handle)) return ws;
    }

    return null;
}

/// Maps a new window by mapping it to the correct
/// workspace and screen to make it 'visible'.
pub fn mapWindow(self: *LayoutManager, window: Window) !void {
    const workspace = self.active();
    try workspace.add(self.gpa, window);

    try self.remapWindows();

    // Listen to events
    try window.changeAttributes(&[_]x.protocol.ValueMask{.{
        .mask = .event_mask,
        .value = window_event_mask.toInt(),
    }});

    // Map it to the screen
    try window.map();

    // Set border colour optionally and set the `focused` property on the workspace
    // as well as giving the window input focus
    try self.focusWindow(window);

    log.debug("Mapped window {d} on workspace {d}", .{ window.handle, workspace.id });
}

/// When a destroy notify is triggered or when a user explicitly wants to close a window
/// this can be called to close it and also remove its reference from the workspace
pub fn closeWindow(self: *LayoutManager, handle: x.protocol.Types.Window) !void {
    const workspace = self.find(handle) orelse return;

    // remove it from the workspace we found
    const deleted = workspace.remove(handle).?;

    // If the deleted window was focused, focus the first window on the workspace
    if (workspace.focused) |focused| {
        if (focused.handle == deleted.handle and workspace.items().len > 0) {
            workspace.focused = null;
            try self.focusWindow(workspace.items()[0]);
        }
    }

    try self.remapWindows();
}

/// Focuses the window and sets the focused-border-colour if border_width is set on the user config
pub fn focusWindow(self: *LayoutManager, window: Window) !void {
    const workspace = self.active();

    // save old focused window in temp variable so we can remove border colour later
    const old_focused = workspace.focused;

    workspace.focused = window;

    // set input focus to the window
    try window.inputFocus();

    // don't set any border colours if the `border_width` is null
    if (config.border_width == null) return;

    try window.changeAttributes(&[_]x.protocol.ValueMask{.{
        .mask = .border_pixel,
        .value = config.border_color_focused,
    }});

    if (old_focused) |old| {
        try old.changeAttributes(&[_]x.protocol.ValueMask{.{
            .mask = .border_pixel,
            .value = config.border_color_unfocused,
        }});
    }
}

/// Switches the another workspace at index `idx`
pub fn switchTo(self: *LayoutManager, idx: usize) !void {
    if (idx >= self.workspaces.len) return error.OutOfBounds;

    // unmap all current windows
    for (self.active().items()) |window| try window.unMap();

    self.current = idx;
    std.debug.assert(self.active().id == idx);

    // map all windows on the new active workspace
    for (self.active().items()) |window| try window.map();
}

/// Restacks all the windows that are currently mapped on the screen
fn remapWindows(self: *LayoutManager) !void {
    // if only 1 window, make it full screen (with respect to borders)
    const workspace = self.active();
    const mask = x.protocol.WindowConfigMask{
        .x = true,
        .y = true,
        .width = true,
        .height = true,
        .border_width = true,
    };

    const border_width = config.border_width orelse 0;

    if (workspace.items().len == 1) {
        try workspace.items()[0].configure(mask, .{
            .width = self.size.width - (border_width * 2),
            .height = self.size.height - (border_width * 2),
            .border_width = config.border_width orelse 0,
        });
        return;
    }

    const width: u16 = @divFloor(self.size.width - (border_width * 4), 2);

    for (workspace.items()) |window, i| {
        const x_pos: i16 = if (i == 0) 0 else @intCast(i16, width + border_width * 2);
        var height: u16 = self.size.height - (border_width * 2);
        var y_pos: i16 = 0;

        if (i > 0) {
            const right_windows: u16 = @intCast(u16, workspace.items().len - 1);
            height = @divTrunc(
                height - @intCast(u16, (right_windows - 1) * (border_width * 2)),
                @intCast(u16, right_windows),
            );
            y_pos += @intCast(i16, i - 1) * @intCast(i16, height + (border_width * 2));
        }

        std.debug.print("Window: {d} - Width: {d} - Height: {d} - x: {d} - y: {d} \n", .{
            window.handle,
            width,
            height,
            x_pos,
            y_pos,
        });
        try window.configure(mask, .{
            .width = width,
            .height = height,
            .x = x_pos,
            .y = y_pos,
            .border_width = border_width,
        });
    }
}
