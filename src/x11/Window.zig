const x = @import("protocol.zig");
const Connection = @import("Connection.zig");
const Context = @import("Context.zig");
const std = @import("std");
const os = std.os;
const mem = std.mem;

pub const Window = @This();

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
};

/// The mode you want to change the window property
/// For example, to append to the window title you use .Append
const PropertyMode = enum(u8) {
    replace,
    prepend,
    append,
};

/// Creates a new `Window` on the given `screen` using the settings, set by `options`
pub fn create(conn: *Connection, screen: Connection.Screen, options: CreateWindowOptions) !Window {
    const xid = try conn.genXid();
    const event_mask: u32 = x.Values.BUTTON_PRESS | x.Values.BUTTON_RELEASE | x.Values.KEY_PRESS |
        x.Values.KEY_RELEASE;
    const writer = conn.handle.writer();

    const window_request = x.CreateWindowRequest{
        .length = @sizeOf(x.CreateWindowRequest) / 4 + 2,
        .wid = xid,
        .parent = screen.root,
        .width = options.width,
        .height = options.height,
        .visual = screen.root_visual,
        .value_mask = x.Values.BACK_PIXEL | x.Values.EVENT_MASK,
    };

    const map_request = x.MapWindowRequest{
        .window = xid,
    };

    try writer.writeAll(std.mem.asBytes(&window_request));
    try writer.writeAll(std.mem.asBytes(&screen.black_pixel));
    try writer.writeAll(std.mem.asBytes(&event_mask));
    try writer.writeAll(std.mem.asBytes(&map_request));

    const window = Window{ .handle = xid, .connection = conn };

    if (options.title) |title| {
        _ = async window.changeWindowProperty(
            .replace,
            x.Atoms.wm_name,
            x.Atoms.string,
            .{ .string = title },
        );
    }

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
fn changeWindowProperty(
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

/// Creates a new `Context` for this `Window` with the given `mask` and `values`
fn createContext(self: Window, mask: u32, values: []u32) !x.Types.GContext {
    return Context.create(self.connection, self.handle, mask, values);
}

fn xpad(n: usize) usize {
    return @bitCast(usize, (-%@bitCast(isize, n)) & 3);
}
