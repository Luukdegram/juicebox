const x = @import("protocol.zig");
const Connection = @import("Connection.zig");
const Context = @import("Context.zig");
const std = @import("std");
const os = std.os;
const mem = std.mem;

const Window = @This();

//! Window management module. Allows for creation, updating and removing of windows
//! A window also has a reference to the connection that was used to create the window
//! to remove the need to pass around the connection everywhere

/// Xid of the window, used to update settings etc.
handle: x.Types.Window,

/// Non-owning pointer to the connection that was used to create this window
connection: *const Connection,

/// Options to create a new `Window`
/// Allows you to set the `width` and `height` when creating a new `Window`
pub const CreateWindowOptions = struct {
    width: u16,
    height: u16,
    title: ?[]const u8 = null,
    class: WindowClass = .copy,
    values: []const x.ValueMask = &[_]x.ValueMask{},
};

/// The mode you want to change the window property
/// For example, to append to the window title you use .Append
const PropertyMode = enum(u8) {
    replace,
    prepend,
    append,
};

const WindowClass = enum(u16) {
    copy = 0,
    input_output = 1,
    input_only = 2,

    fn toInt(self: WindowClass) u16 {
        return @enumToInt(self);
    }
};

/// Creates a new `Window` on the given `screen` using the settings, set by `options`
/// For now it creates a window with a black background
pub fn create(conn: *Connection, screen: Connection.Screen, options: CreateWindowOptions) !Window {
    const xid = try conn.genXid();
    const writer = conn.handle.writer();

    const mask: u32 = blk: {
        var tmp: u32 = 0;
        for (options.values) |val| tmp |= val.mask.toInt();
        break :blk tmp;
    };

    const window_request = x.CreateWindowRequest{
        .length = @sizeOf(x.CreateWindowRequest) / 4 + @intCast(u16, options.values.len),
        .wid = xid,
        .parent = screen.root,
        .width = options.width,
        .height = options.height,
        .visual = screen.root_visual,
        .value_mask = mask,
        .class = options.class.toInt(),
    };

    try conn.send(window_request);
    for (options.values) |val| try conn.send(val.value);

    const window = Window{ .handle = xid, .connection = conn };

    if (options.title) |title| {
        try window.changeProperty(
            .replace,
            x.Atoms.wm_name,
            x.Atoms.string,
            .{ .string = title },
        );
    }

    // map our window to make it visible
    try window.map();

    return window;
}

/// Property is a union which can be used to change
/// a window property.
/// For now it's only `STRING` and `INTEGER`.
const Property = union(enum) {
    int: u32,
    string: []const u8,

    /// Returns the length of the underlaying data,
    /// Note that for union Int it first converts it to a byte slice,
    /// and then returns the length of that
    fn len(self: Property) u32 {
        return switch (self) {
            .int => 4,
            .string => |array| @intCast(u32, array.len),
        };
    }
};

/// Allows to change a window property using the given parameters
/// such as the window title
pub fn changeProperty(
    self: Window,
    mode: PropertyMode,
    property: x.Types.Atom,
    prop_type: x.Atoms,
    data: Property,
) !void {
    const total_length: u16 = @intCast(u16, @sizeOf(x.ChangePropertyRequest) + data.len() + xpad(data.len())) / 4;
    const writer = self.connection.handle.writer();

    std.debug.assert(switch (data) {
        .int => prop_type == .integer,
        .string => prop_type == .string,
    });

    const request = x.ChangePropertyRequest{
        .mode = @enumToInt(mode),
        .length = total_length,
        .window = self.handle,
        .property = property,
        .prop_type = prop_type.toInt(),
        .data_len = data.len(),
    };

    try self.connection.send(request);
    try switch (data) {
        .int => |int| self.connection.send(int),
        .string => |string| self.connection.send(string),
    };
    // padding to end the data property
    try self.connection.send(request.pad0[0..xpad(data.len())]);
}

/// Changes the given attributs on the current `Window`
pub fn changeAttributes(self: Window, values: []const x.ValueMask) !void {
    const mask: u32 = blk: {
        var tmp: u32 = 0;
        for (values) |val| tmp |= val.mask.toInt();
        break :blk tmp;
    };

    try self.connection.send(
        x.ChangeWindowAttributes{
            .length = @sizeOf(x.ChangeWindowAttributes) / 4 + @intCast(u16, values.len),
            .window = self.handle,
            .mask = mask,
        },
    );
    for (values) |val| try self.connection.send(val.value);
}

/// Configures the window using the given values and mask
pub fn configure(self: Window, mask: x.WindowConfigMask, config: x.WindowChanges) !void {
    try self.connection.send(
        x.ConfigureWindowRequest{
            .length = @sizeOf(x.ConfigureWindowRequest) / 4 + x.maskLen(mask),
            .window = self.handle,
            .mask = mask.toInt(),
        },
    );

    inline for (std.meta.fields(x.WindowConfigMask)) |field| {
        if (field.field_type == bool and @field(mask, field.name)) {
            //@compileLog(@typeInfo(@TypeOf(@field(config, field.name))).Int);
            if (@typeInfo(@TypeOf(@field(config, field.name))).Int.signedness == .signed) {
                try self.connection.send(@as(i32, @field(config, field.name)));
            } else {
                try self.connection.send(@as(u32, @field(config, field.name)));
            }
        }
    }
}

/// Closes a window
pub fn close(self: Window) !void {
    try self.connection.send(x.KillClientRequest{ .window = self.handle });
}

/// Creates a new `Context` for this `Window` with the given `mask` and `values`
pub fn createContext(self: Window, mask: u32, values: []u32) !x.Types.GContext {
    return Context.create(self.connection, self.handle, mask, values);
}

/// Maps a window to the current display
pub fn map(self: Window) !void {
    try self.connection.send(x.MapWindowRequest{ .window = self.handle });
}

/// Unmaps the window and therefore hides it
pub fn unMap(self: Window) !void {
    try self.connection.send(x.MapWindowRequest{ .window = self.handle, .major_opcode = 10 });
}

/// Sets the input focus to the window
pub fn inputFocus(self: Window) !void {
    try self.connection.send(x.SetInputFocusRequest{
        .window = self.handle,
        .time_stamp = 0,
        .revert_to = 1,
    });
}

fn xpad(n: usize) usize {
    return @bitCast(usize, (-%@bitCast(isize, n)) & 3);
}
