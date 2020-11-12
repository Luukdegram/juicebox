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
/// non owning pointer to the connection that was used to create this window
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

    fn val(self: WindowClass) u16 {
        return @enumToInt(self);
    }
};

/// Creates a new `Window` on the given `screen` using the settings, set by `options`
/// For now it creates a window with a black background
pub fn create(conn: *Connection, screen: Connection.Screen, options: CreateWindowOptions, values: []const x.ValueMask) !Window {
    const xid = try conn.genXid();
    const writer = conn.handle.writer();

    const mask: u32 = blk: {
        var tmp: u32 = 0;
        for (values) |val| tmp |= val.mask;
        break :blk tmp;
    };

    const window_request = x.CreateWindowRequest{
        .length = @sizeOf(x.CreateWindowRequest) / 4 + @intCast(u16, values.len),
        .wid = xid,
        .parent = screen.root,
        .width = options.width,
        .height = options.height,
        .visual = screen.root_visual,
        .value_mask = mask,
        .class = options.class.val(),
    };

    try conn.send(window_request);
    for (values) |val| try conn.send(val.value);

    // map our window to make it visible
    try map(conn, xid);

    const window = Window{ .handle = xid, .connection = conn };

    defer if (options.title) |title| {
        _ = async window.changeProperty(
            .replace,
            x.Atoms.wm_name,
            x.Atoms.string,
            .{ .string = title },
        );
    };

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
    property: x.Atoms,
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
        .property = property.val(),
        .prop_type = prop_type.val(),
        .data_len = data.len(),
    };

    try self.connection.send(request);
    try switch (data) {
        .int => |int| self.connection.send(int),
        .string => |string| self.connection.send(string),
    };
    // padding to end the data property
    try self.connection.send(request.pad0);
}

/// Changes the given attributs on the current `Window`
pub fn changeAttributes(self: Window, values: []const x.ValueMask) !void {
    const mask: u32 = blk: {
        var tmp: u32 = 0;
        for (values) |val| tmp |= val.mask;
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
pub fn configure(self: Window, values: []const x.ValueMask) !void {
    const mask: u32 = blk: {
        var tmp: u32 = 0;
        for (values) |val| tmp |= val.mask;
        break :blk tmp;
    };

    try self.connection.send(
        x.ConfigureWindowRequest{
            .length = @sizeOf(x.ChangeWindowAttributes) / 4 + @intCast(u16, values.len),
            .window = self.handle,
            .mask = mask,
        },
    );
    for (values) |val| try self.connection.send(val.value);
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
pub fn map(connection: *Connection, window: x.Types.Window) !void {
    try connection.send(x.MapWindowRequest{ .window = window });
}

fn xpad(n: usize) usize {
    return @bitCast(usize, (-%@bitCast(isize, n)) & 3);
}
