const std = @import("std");
const Manager = @import("Manager.zig");
const log = std.log.scoped(.juicebox_actions);

/// Switches to the workspace defined in `arg`
pub fn switchWorkspace(manager: *Manager, arg: u4) !void {
    var layout = manager.layout_manager;
    if (arg >= layout.workspaces.len) {
        log.notice(
            "arg for action [switchWorkspace] is too big. Only {d} workspaces exist",
            .{layout.workspaces.len},
        );
        return;
    }

    try layout.switchTo(arg);
}

/// Closes the currently focused window
pub fn closeWindow(manager: *Manager) !void {
    if (manager.layout_manager.active().focused) |focused| {
        // this will trigger a destroy_notify so layout manager will handle the rest
        try focused.close();
    }
}

/// Moves the focused window to a different workspace specified by `arg`
pub fn moveWindow(manager: *Manager, arg: u4) !void {
    var layout = manager.layout_manager;
    if (arg >= layout.workspaces.len) {
        log.notice(
            "arg for action [switchWorkspace] is too big. Only {d} workspaces exist",
            .{layout.workspaces.len},
        );
        return;
    }

    // if a window is focused, move it to the given workspace
    if (layout.active().focused) |focused_window| try layout.moveWindow(focused_window, arg);
}

/// Toggles between tiled and fullscreen mode for the current workspace
/// the `arg` argument is ignored
pub fn toggleFullscreen(manager: *Manager) !void {
    try manager.layout_manager.toggleFullscreen();
}

/// Swaps the window according to the given `arg`. For example:
/// when `arg` is `.right` swaps the focused window with the window to the right of it
/// but only when the window is on the left hand side of the screen.
pub fn swapWindow(manager: *Manager, comptime arg: @Type(.EnumLiteral)) !void {
    switch (arg) {
        .left, .right, .up, .down => try manager.layout_manager.swapWindow(arg),
        else => return error.InvalidEnum,
    }
}

/// Swaps the focus between windows according to given `arg`.
/// For example, when providing `.right` while having the left hand window focused
/// will move the focus to the top right window
pub fn swapFocus(manager: *Manager, comptime arg: @Type(.EnumLiteral)) !void {
    switch (arg) {
        .left, .right, .up, .down => try manager.layout_manager.swapFocus(arg),
        else => return error.InvalidEnum,
    }
}
