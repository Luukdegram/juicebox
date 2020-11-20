const std = @import("std");
const x = @import("x11");
const config = @import("config.zig").default_config;
const Workspace = @import("Workspace.zig");
const Window = x.Window;
const Allocator = std.mem.Allocator;

const LayoutManager = @This();

//! This contains the layour manager. It is being called by the
//! Manager whenever a new window is created/updated/removed to ensure
//! all windows align with the selected layout rules.

const Workspaces = [config.workspaces]Workspace;

/// The list of workspaces
workspaces: Workspaces,
/// The currently active workspace being displayed on the monitor
current: usize,
/// An allocator, used to add new Windows to a workspace and manage
/// the memory of the workspaces
gpa: *Allocator,

/// Initializes a new instance of `LayoutManager` and initializes all workspaces
pub fn init(gpa: *Allocator) LayoutManager {
    var self = LayoutManager{
        .workspaces = undefined,
        .current = 0,
        .gpa = gpa,
    };

    for (self.workspaces) |*ws, i| ws.* = Workspace.init(i);

    return self;
}

/// Frees the resources of the `LayoutManager`
pub fn deinit(self: *LayoutManager) void {
    for (self.workspaces) |ws| ws.deinit(self.gpa);
}
