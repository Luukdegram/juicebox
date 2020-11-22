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
