const std = @import("std");
const x = @import("x11");
const config = @import("config.zig").default_config;
const Workspace = @import("Workspace.zig");
const Window = x.Window;
const Allocator = std.mem.Allocator;
const events = x.events;

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
fn active(self: *LayoutManager) *Workspace {
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

/// Maps a new window by setting its dimensions and then mapping it to the correct
/// workspace and screen to make it 'visible'.
pub fn mapWindow(self: *LayoutManager, window: Window) !void {
    //Maps requests are only done by newly created windows so add it to the workspace list
    try self.active().add(self.gpa, window);

    try window.configure(.{
        .width = true,
        .height = true,
        .border_width = true,
    }, .{
        .width = self.size.width,
        .height = self.size.height,
        .border_width = config.border_width orelse 0,
    });

    try window.changeAttributes(&[_]x.protocol.ValueMask{.{
        .mask = .event_mask,
        .value = window_event_mask.toInt(),
    }});

    // Set border colour optionally and set the `focused` property on the workspace
    try self.focusWindow(self.active(), window);

    // Map it to the screen
    try window.map();

    // finally, give the window input focus
    try window.focus();
}

/// When a destroy notify is triggered or when a user explicitly wants to close a window
/// this can be called to close it and also remove its reference from the workspace
pub fn closeWindow(self: *LayoutManager, handle: x.protocol.Types.Window) !void {
    const workspace = self.find(handle) orelse return;

    // remove it from the workspace we found
    const deleted = workspace.remove(handle).?;

    // If the deleted window was focused, focus the first window on the workspace
    if (workspace.focused) |focused| {
        if (focused.handle == deleted.handle and workspace.items().len > 0)
            try self.focusWindow(workspace, workspace.items()[0]);
    }

    //TODO trigger layout update
}

/// Focuses the window and sets the focused-border-colour if border_width is set on the user config
pub fn focusWindow(self: LayoutManager, workspace: *Workspace, window: Window) !void {
    workspace.focused = window;

    // don't set any border colours if the `border_width` is null
    if (config.border_width == null) return;

    try window.changeAttributes(&[_]x.protocol.ValueMask{.{
        .mask = .border_pixel,
        .value = config.border_color_focused,
    }});
}
