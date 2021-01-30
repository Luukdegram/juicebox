const std = @import("std");
const x = @import("x11");
const config = @import("config.zig").default_config;
const Workspace = @import("Workspace.zig");
const Window = x.Window;
const Allocator = std.mem.Allocator;
const events = x.events;
const log = std.log.scoped(.juicebox);

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
    for (self.workspaces) |*ws| ws.deinit(self.gpa);
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

    try self.remapWindows(workspace);

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
    for (self.workspaces) |*workspace, i| {
        if (!workspace.contains(handle)) continue;

        // If the deleted window was focused, focus the first window on the workspace
        if (workspace.focused) |focused| {
            workspace.focused = null;
            if (focused.handle == handle and workspace.prev(focused) != null) {
                try self.focusWindow(workspace.prev(focused).?);
            }
        }

        // remove it from the workspace we found
        _ = workspace.remove(handle).?;

        try self.remapWindows(workspace);

        log.debug("Closed window {d} from workspace {d}", .{ handle, i });
    }
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

    log.debug("Set focus to window {d}", .{window.handle});
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

    // make sure to give input focus to our focused window
    if (self.active().focused) |focused| try self.focusWindow(focused);

    log.debug("Switch to workspace {d}", .{idx});
}

/// Moves a `Window` `window` to workspace `idx`
pub fn moveWindow(self: *LayoutManager, window: Window, idx: usize) !void {
    if (idx >= self.workspaces.len) return error.OutOfBounds;

    // first focus the previous window
    if (self.active().prev(window)) |prev|
        try self.focusWindow(prev)
    else
        self.active().focused = null;

    // Them remove it from the current workspace
    _ = self.active().remove(window.handle);
    // and unmap it too
    try window.unMap();

    // Add it to the new workspace
    try self.workspaces[idx].add(self.gpa, window);
    // give it focus
    self.workspaces[idx].focused = window;

    // Make sure the layout is consistent:
    try self.remapWindows(&self.workspaces[idx]);
    // as well as the current workspace
    try self.remapWindows(self.active());

    log.debug("Moved window {d} to workspace {d}", .{ window.handle, idx });
}

/// Toggles between tiled and fullscreen mode for the active workspace
pub fn toggleFullscreen(self: *LayoutManager) !void {
    const current = self.active();
    if (current.mode == .full_screen) {
        try self.remapWindows(current);
        current.mode = .tiled;
    } else {
        if (current.focused) |window| {
            try window.configure(
                .{ .width = true, .height = true, .x = true, .y = true, .border_width = true, .stack_mode = true },
                .{ .width = self.size.width, .height = self.size.height, .x = 0, .y = 0, .border_width = 0, .stack_mode = 0 },
            );
        }
        current.mode = .full_screen;
    }
}

/// Swaps the focused window with the window according to the given `direction`
/// A window must be focused, and the window must be able to be moved to the given area
pub fn swapWindow(self: *LayoutManager, direction: enum { left, right, up, down }) !void {
    const current = self.active();
    const focused = current.focused orelse return;
    const idx = current.getIdx(focused) orelse return;
    const len = current.items().len;

    switch (direction) {
        .left => {
            // make sure the window is not left hand side
            if (idx == 0) return;
            current.swap(idx, 0); // swaps with left window
        },
        .right => {
            // make sure the window is not on right hand side
            if (idx > 0 or len < 2) return;
            current.swap(idx, 1);
        },
        .up => {
            // make sure window is on right hand side and not top
            if (idx < 2 or len < 3) return;
            current.swap(idx, idx - 1);
        },
        .down => {
            // make sure window is on right hand side and not bottom
            if (idx == 0 or idx == current.items().len - 1) return;
            current.swap(idx, idx + 1);
        },
    }

    try self.remapWindows(current);
}

/// Swaps the focus between windows according to given `direction`.
/// I.e. swap the focus from the left window to the right top window.
pub fn swapFocus(self: *LayoutManager, direction: enum { left, right, up, down }) !void {
    const current = self.active();
    const focused = current.focused orelse return;
    const idx = current.getIdx(focused) orelse return;
    const len = current.items().len;

    switch (direction) {
        .left => {
            // make sure the window is not left hand side
            if (idx == 0) return;
            try self.focusWindow(current.getByIdx(0));
        },
        .right => {
            // make sure the window is not on right hand side
            if (idx > 0 or len < 2) return;
            try self.focusWindow(current.getByIdx(1));
        },
        .up => {
            // make sure window is on right hand side and not top
            if (idx < 2 or len < 3) return;
            try self.focusWindow(current.getByIdx(idx - 1));
        },
        .down => {
            // make sure window is on right hand side and not bottom
            if (idx == 0 or idx == current.items().len - 1) return;
            try self.focusWindow(current.getByIdx(idx + 1));
        },
    }
}

/// Pins or unpin the focused window by making it available in all workspaces
/// or only the current workspace when unpinning
pub fn pinFocus(self: *LayoutManager) !void {
    const focused = self.active().focused orelse return;

    for (self.workspaces) |*ws, i| {
        if (ws == self.active()) continue; //skip for current workspace

        if (ws.getIdx(focused)) |idx| {
            _ = ws.remove(focused.handle);
            log.debug("Unpinned from workspace {d}", .{i});
        } else {
            try ws.add(self.gpa, focused);
            ws.focused = focused;
            log.debug("Pinned to workspace {d}", .{i});
        }
    }
}

/// Restacks all the windows that are currently mapped on the screen
fn remapWindows(self: *LayoutManager, workspace: *Workspace) !void {
    // if only 1 window, make it full screen (with respect to borders)
    const mask = x.protocol.WindowConfigMask{
        .x = true,
        .y = true,
        .width = true,
        .height = true,
        .border_width = true,
    };

    // get configured border sizes, orelse 0
    const border_width = config.border_width orelse 0;
    // get configured gaps, orelse defaults (all 0)
    const gaps = config.gaps orelse @import("config.zig").GapOptions{};

    if (workspace.items().len == 1) {
        try workspace.items()[0].configure(mask, .{
            .width = self.size.width - (border_width * 2),
            .height = self.size.height - (border_width * 2),
            .border_width = config.border_width orelse 0,
        });
        return;
    }

    const gap_width = (gaps.left + gaps.right) * 2;
    const gap_height = gaps.top + gaps.bottom;
    const width: u16 = @divFloor(self.size.width - gap_width - (border_width * 4), 2);

    for (workspace.items()) |window, i| {
        // set x position (left is 0)
        const x_pos: i16 = if (i == 0)
            gaps.left
        else
            @intCast(i16, width + (gaps.left + gaps.right + gaps.left) + (border_width * 2));

        // calculate the height per full size window
        var height: u16 = self.size.height - gaps.top - gaps.bottom - (border_width * 2);

        // base y position (top is 0)
        var y_pos: i16 = gaps.top;

        if (i > 0) {
            const right_windows: u16 = @intCast(u16, workspace.items().len - 1);
            height = @divTrunc(
                height - @intCast(u16, (right_windows - 1) * ((border_width * 2) + (gap_height))),
                @intCast(u16, right_windows),
            );
            y_pos += @intCast(i16, i - 1) * @intCast(i16, height + (border_width * 2) + gap_height);
        }

        try window.configure(mask, .{
            .width = width,
            .height = height,
            .x = x_pos,
            .y = y_pos,
            .border_width = border_width,
        });
    }
}
