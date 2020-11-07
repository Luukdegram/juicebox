const x = @import("protocol.zig");
const Connection = @import("Connection.zig");
const Context = @import("Context.zig");
const os = @import("std").os;

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
};

/// Creates a new `Window` on the given `screen` using the settings, set by `options`
pub fn create(conn: *Connection, screen: Connection.Screen, options: CreateWindowOptions) !Window {
    const xid = try conn.genXid();
    const event_mask: u32 = x.Values.BUTTON_PRESS | x.Values.BUTTON_RELEASE | x.Values.KEY_PRESS |
        x.Values.KEY_RELEASE;

    const window_request = x.CreateWindowRequest{
        .length = @sizeOf(x.CreateWindowRequest) / 4 + 2,
        .wid = xid,
        .parent = screen.root,
        .width = options.width,
        .height = options.height,
        .visual = screen.root_visual,
        .value_mask = x.Values.BACK_PIXEL | x.Values.EVENT_MASK,
    };
    var parts: [4]os.iovec_const = undefined;
    parts[0].iov_base = @ptrCast([*]const u8, &window_request);
    parts[0].iov_len = @sizeOf(x.CreateWindowRequest);
    parts[1].iov_base = @ptrCast([*]const u8, &screen.black_pixel);
    parts[1].iov_len = 4;
    parts[2].iov_base = @ptrCast([*]const u8, &event_mask);
    parts[2].iov_len = 4;

    const map_request = x.MapWindowRequest{
        .length = @sizeOf(x.MapWindowRequest) / 4,
        .window = xid,
    };
    parts[3].iov_base = @ptrCast([*]const u8, &map_request);
    parts[3].iov_len = @sizeOf(x.MapWindowRequest);

    try conn.handle.writevAll(&parts);

    const window = Window{ .handle = xid, .connection = conn };

    return window;
}

/// Creates a new `Context` for this `Window` with the given `mask` and `values`
fn createContext(self: *Window, mask: u32, values: []u32) !x.Types.GContext {
    return Context.create(self.connection, self.handle, mask, values);
}
