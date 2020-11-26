const x11 = @import("x11");
const actions = @import("actions.zig");
const keys = x11.keys;
const input = x11.input;
const Keysym = x11.protocol.Types.Keysym;

//! User defined configuration of Juicebox
//! Currently this file requires to be changed to update the configuration.
//! In the future, the user can pass a path to a config file during compilation
//! that will overwrite this config. However, the goal remains to have the config
//! available in the static data section and not allocate any memory for it.
//! Runtime memory is more important than binary size for now.

/// The action to perform when a keybinding has been triggered
/// use `function` when a function has to be ran by the manager.
/// Or use `cmd` when a shell command must be ran.
pub const Action = union(ActionType) {
    /// The function to call on key press and the argument
    function: struct { action: actions.Action, arg: anytype },
    /// The shell command to execute
    cmd: []const []const u8,

    pub const ActionType = enum { function, cmd };
};

/// Single keybind and its action
pub const KeyBind = struct {
    /// Keyboard symbol to fire the event
    symbol: Keysym,
    /// Optional modifier needed to press above symbol. `Any` by default
    modifier: input.Modifiers = input.Modifiers.any,
    /// The action to perform. I.e. close a window by using `function`
    /// or running a command such as dmenu by using `cmd`.
    action: Action,
};

/// Alias to a list of keybindings
pub const Keybindings = []const KeyBind;

/// User defined configuration struct
/// Allows the user to apply different effects of Juicebox
pub const Config = struct {
    /// Lost of keybindings
    bindings: Keybindings,
    /// Border width for windows. Null by default, meaning no border effect
    border_width: ?u16 = null,
    /// Border color when a window is unfocused. Ignored when `border_width` is null
    border_color_unfocused: u32 = 0x34bdeb,
    /// Border color when a window is focused. Ignored when `border_width` is null
    border_color_focused: u32 = 0x014c82,
    /// The amount of workspaces Juicebox should contain. Can hold a maximum of 16
    workspaces: u4 = 10,
    /// Gap sizes between windows. No gaps if null (default)
    gaps: ?GapOptions = null,
};

/// Allows the user to set gap sizes between windows
pub const GapOptions = struct {
    left: u16 = 0,
    right: u16 = 0,
    top: u16 = 0,
    bottom: u16 = 0,
};

/// The default config when no configuration has been provided
/// This can either be manually changed in the source code,
/// or by providing -Dconfig=<config_path>
pub const default_config: Config = .{
    // enable borders and set its width
    .border_width = 1,

    // enable gap sizes
    .gaps = .{ .left = 4, .right = 4, .top = 4, .bottom = 4 },

    // define keybindings and their actions
    .bindings = &[_]KeyBind{
        .{
            .symbol = keys.XK_q,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.closeWindow, .arg = {} } },
        },
        .{
            .symbol = keys.XK_d,
            .modifier = .{ .mod4 = true },
            .action = .{ .cmd = &[_][]const u8{"dmenu_run"} },
        },
        .{
            .symbol = keys.XK_f,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.toggleFullscreen, .arg = {} } },
        },
        .{
            .symbol = keys.XK_Return,
            .modifier = .{ .mod4 = true },
            .action = .{ .cmd = &[_][]const u8{"alacritty"} },
        },
        .{
            .symbol = keys.XK_1,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 0) } },
        },
        .{
            .symbol = keys.XK_2,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 1) } },
        },
        .{
            .symbol = keys.XK_3,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 2) } },
        },
        .{
            .symbol = keys.XK_4,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 3) } },
        },
        .{
            .symbol = keys.XK_5,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 4) } },
        },
        .{
            .symbol = keys.XK_6,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 5) } },
        },
        .{
            .symbol = keys.XK_7,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 6) } },
        },
        .{
            .symbol = keys.XK_8,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 7) } },
        },
        .{
            .symbol = keys.XK_9,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 8) } },
        },
        .{
            .symbol = keys.XK_0,
            .modifier = .{ .mod4 = true },
            .action = .{ .function = .{ .action = actions.switchWorkspace, .arg = @as(u4, 9) } },
        },
        .{
            .symbol = keys.XK_1,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 0 } },
        },
        .{
            .symbol = keys.XK_2,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 1 } },
        },
        .{
            .symbol = keys.XK_3,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 2 } },
        },
        .{
            .symbol = keys.XK_4,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 3 } },
        },
        .{
            .symbol = keys.XK_5,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 4 } },
        },
        .{
            .symbol = keys.XK_6,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 5 } },
        },
        .{
            .symbol = keys.XK_7,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 6 } },
        },
        .{
            .symbol = keys.XK_8,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 7 } },
        },
        .{
            .symbol = keys.XK_9,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 8 } },
        },
        .{
            .symbol = keys.XK_0,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.moveWindow, .arg = 9 } },
        },
        .{
            .symbol = keys.XK_Right,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.swapWindow, .arg = .right } },
        },
        .{
            .symbol = keys.XK_Left,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.swapWindow, .arg = .left } },
        },
        .{
            .symbol = keys.XK_Up,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.swapWindow, .arg = .up } },
        },
        .{
            .symbol = keys.XK_Down,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = .{ .action = actions.swapWindow, .arg = .down } },
        },
    },
};
