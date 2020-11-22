const std = @import("std");
const Manager = @import("Manager.zig");
const log = std.log.scoped(.juicebox_actions);

/// Function signature for actions users can call on keybinds
pub const Action = fn (*Manager, anytype) anyerror!void;

/// Switches to the workspace defined in `arg`
pub fn switchWorkspace(manager: *Manager, arg: anytype) !void {
    const typeInfo = @typeInfo(@TypeOf(arg));
    if (typeInfo != .Int and typeInfo != .ComptimeInt) return;
    if (typeInfo != .ComptimeInt and typeInfo.Int.bits > 4) return;

    const layout = manager.layout_manager;
    if (layout.workspaces.len < arg) {
        log.notice(
            "arg for action [switchWorkspace] is too big. Only {d} workspaces exist",
            .{layout.workspaces.len},
        );
        return;
    }
}

/// Closes the currently focused window
pub fn closeWindow(manager: *Manager, arg: anytype) !void {
    if (manager.layout_manager.active().focused) |focused| {
        try manager.layout_manager.closeWindow(focused.handle);
        try focused.close();
    }
}
