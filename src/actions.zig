const std = @import("std");
const Manager = @import("Manager.zig");
const log = std.log.scoped(.juicebox_actions);

/// Function signature for actions users can call on keybinds
pub const Action = fn (*Manager, anytype) anyerror!void;

/// Switches to the workspace defined in `arg`
pub fn switchWorkspace(manager: *Manager, arg: anytype) !void {
    const typeInfo = @typeInfo(@TypeOf(arg));
    if (typeInfo != .Int and typeInfo != .ComptimeInt) @compileError("Expected an Int or ComptimeInt as argument");
    if (typeInfo != .ComptimeInt and typeInfo.Int.bits > 4) @compileError("Int bits too big");

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
pub fn closeWindow(manager: *Manager, arg: anytype) !void {
    if (manager.layout_manager.active().focused) |focused| {
        // this will trigger a destroy_notify so layout manager will handle the rest
        try focused.close();
    }
}

/// Moves the focused window to a different workspace specified by `arg`
pub fn moveWindow(manager: *Manager, arg: anytype) !void {
    const typeInfo = @typeInfo(@TypeOf(arg));
    if (typeInfo != .Int and typeInfo != .ComptimeInt) @compileError("Expected an Int or ComptimeInt as argument");
    if (typeInfo != .ComptimeInt and typeInfo.Int.bits > 4) @compileError("Int bits too big");

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
pub fn toggleFullscreen(manager: *Manager, arg: anytype) !void {
    try manager.layout_manager.toggleFullscreen();
}

/// Swaps the window according to the given `arg`. For example:
/// when `arg` is `.right` swaps the focused window with the window to the right of it
/// but only when the window is on the left hand side of the screen.
pub fn swapWindow(manager: *Manager, arg: anytype) !void {
    const typeInfo = @typeInfo(@TypeOf(arg));
    if (typeInfo != .EnumLiteral) @compileError("Expected an EnumLiteral, but found a different type");

    switch (arg) {
        .left, .right, .up, .down => try manager.layout_manager.swapWindow(arg),
        else => return error.InvalidEnum,
    }
}
