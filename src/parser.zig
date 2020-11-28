const std = @import("std");
const mem = std.mem;
usingnamespace @import("config.zig");

/// Parses the input data and returns an instance of `Config`
pub fn parseConfig(comptime data: []const u8) Config {
    @setEvalBranchQuota(50_000);
    var keybinds: Keybindings = &[_]KeyBind{};
    var config = Config{ .bindings = undefined };

    var lines = std.mem.split(data, "\n");
    while (lines.next()) |line| {
        if (mem.startsWith(u8, line, "keybind")) {
            keybinds = keybinds ++ [_]KeyBind{parseKeybind(line)};
            continue;
        }
        if (mem.startsWith(u8, line, "gaps")) {
            config.gaps = parseGaps(line);
            continue;
        }
        if (mem.startsWith(u8, line, "border")) {
            parseBorders(&config, line);
            continue;
        }
        if (mem.startsWith(u8, line, "workspaces")) {
            config.workspaces = std.fmt.parseInt(u4, line["workspaces".len + 1 ..], 10) catch
            |err| @compileError("Could not parse workspace length: " ++ @errorName(err));
            continue;
        }
    }
    config.bindings = keybinds;
    return config;
}

/// parses the given line into a `GapOptions` struct
fn parseGaps(comptime line: []const u8) GapOptions {
    var it = mem.split(line, " ");
    var options = GapOptions{};

    // ignore first because it contains the "gap" word
    _ = it.next() orelse unreachable;

    inline for (std.meta.fields(GapOptions)) |field| {
        const temp_val = it.next() orelse @compileError("Missing parameter for field " ++ field.name);
        @field(options, field.name) = std.fmt.parseInt(u16, temp_val, 10) catch
        |err| @compileError("Could not parse value for field " ++ field.name ++ ". Error: " ++ @errorName(err));
    }

    return options;
}

/// Parses the line  and sets the right border values on the given `Config` pointer
fn parseBorders(comptime config: *Config, comptime line: []const u8) void {
    var it = mem.split(line, " ");

    // skip first
    _ = it.next() orelse unreachable;

    const option = it.next() orelse @compileError("Missing border option such as [focused|unfocused|width]");
    const temp_val = it.next() orelse @compileError("Missing parameter for border option");
    if (mem.eql(u8, option, "width")) {
        config.border_width = std.fmt.parseInt(u16, temp_val, 10) catch
        |err| @compileError("Could not parse parameter when setting border width. Error: " ++ @errorName(err));
        return;
    }
    if (mem.eql(u8, option, "focused")) {
        config.border_color_focused = std.fmt.parseInt(u32, temp_val, 0) catch
        |err| @compileError("Could not parse parameter when setting border focused colour. Error: " ++ @errorName(err));
        return;
    }
    if (mem.eql(u8, option, "unfocused")) {
        config.border_color_unfocused = std.fmt.parseInt(u32, temp_val, 0) catch
        |err| @compileError("Could not parse parameter when setting border unfocused colour. Error: " ++ @errorName(err));
        return;
    }

    @compileError("Expected border option such as [focused|unfocused|width], but found " ++ option);
}

/// Parses a line into a Keybind object
fn parseKeybind(comptime line: []const u8) KeyBind {
    var it = mem.split(line, " ");

    // skip "keybind"
    _ = it.next() orelse unreachable;

    var keybind = KeyBind{ .modifier = .{}, .symbol = undefined, .action = undefined };

    const modifiers = it.next() orelse @compileError("Expected modifier keys i.e. 'keybind mod4 ....'");

    var modifier_it = mem.split(modifiers, ",");
    while (modifier_it.next()) |mod| {
        if (@hasField(@TypeOf(keybind.modifier), mod)) {
            @field(keybind.modifier, mod) = true;
        }
    }

    const key_code = it.next() orelse @compileError("Expected keysym such as `KX_k` for the `k` key");

    const keysymbols = @import("x11").keys;
    if (@hasDecl(keysymbols, key_code)) {
        keybind.symbol = @field(keysymbols, key_code);
    } else @compileError("Non-existing keysymbol used: " ++ key_code);

    const action_type = it.next() orelse @compileError("Expected [exec|call] but found nothing");

    if (mem.eql(u8, action_type, "call")) {
        const func_name = it.next() orelse @compileError("Expected function name");
        const actions = @import("actions.zig");
        if (@hasDecl(actions, func_name)) {
            const Fn = @typeInfo(@TypeOf(@field(actions, func_name))).Fn;
            if (Fn.args.len == 1) {
                keybind.action = .{ .function = .{ .action = @field(actions, func_name), .arg = {} } };
            } else if (Fn.args.len == 2) {
                const arg_val = it.next() orelse @compileError("Expected another argument after function name");
                const ArgType = Fn.args[1].arg_type.?;
                keybind.action = .{
                    .function = .{
                        .action = @field(actions, func_name),
                        .arg = switch (ArgType) {
                            []const u8 => arg_val,
                            else => switch (@typeInfo(ArgType)) {
                                .Int, .ComptimeInt => std.fmt.parseInt(ArgType, arg_val, 0) catch
                                |err| @compileError("Could not parse argument into integer. Error: " ++ @errorName(err)),
                                .EnumLiteral => if (mem.eql(u8, arg_val, "left"))
                                    .left
                                else if (mem.eql(u8, arg_val, "right"))
                                    .right
                                else if (mem.eql(u8, arg_val, "up"))
                                    .up
                                else if (mem.eql(u8, arg_val, "down"))
                                    .down
                                else
                                    @compileError("Unsupported enum value '" ++ arg_val ++ "'. Must be [left|right|up|down]"),
                                else => @compileError("Unsupported type " ++ @typeName(ArgType)),
                            },
                        },
                    },
                };
            } else @compileError("Config only supports 2 parameters max");
        } else @compileError("The function '" ++ func_name ++ "' is not defined in actions.zig");
    } else if (mem.eql(u8, action_type, "exec")) {
        const executable = it.next() orelse @compileError("Expected exec cmd");
        var cmds: []const []const u8 = &[_][]const u8{executable};
        while (it.next()) |arg| {
            cmds = cmds ++ arg;
        }
        keybind.action = .{ .cmd = cmds };
    } else @compileError("Expected [exec|call] but found " ++ action_type);

    return keybind;
}
