const x11 = @import("x11");
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
    function: []const u8,
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
    /// The default window width a newly created window will have
    /// in floating mode
    window_width: u32 = 800,
    /// The default window height a newly created window will have
    /// in floating mode
    window_height: u32 = 600,
    /// Border width for windows. Null by default, meaning no border effect
    border_width: ?u32 = null,
    /// Border color when a window is unfocused. Ignored when `border_width` is null
    border_color_unfocused: u32 = 0x575859,
    /// Border color when a window is focused. Ignored when `border_width` is null
    border_color_focused: u32 = 0x9fb9d6,
};

/// The default config when no configuration has been provided
/// This can either be manually changed in the source code,
/// or by providing -Dconfig=<config_path>
pub const default_config: Config = .{
    .border_width = 2,
    .bindings = &[_]KeyBind{
        .{
            .symbol = keys.XK_q,
            .modifier = .{ .mod4 = true, .shift = true },
            .action = .{ .function = "close" },
        },
        .{
            .symbol = keys.XK_t,
            .modifier = .{ .mod4 = true },
            .action = .{ .cmd = &[_][]const u8{"dmenu_run"} },
        },
    },
};
