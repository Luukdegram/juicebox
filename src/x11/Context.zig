const x = @import("protocol.zig");
const Connection = @import("Connection.zig");
const os = @import("std").os;

/// Creates a new context and returns its id
/// `root` is the xid of the window that owns the graphics context
pub fn create(connection: *Connection, root: u32, mask: u32, values: []u32) !x.Types.GContext {
    const xid = try connection.genXid();

    const request = x.CreateGCRequest{
        .length = @sizeOf(x.CreateGCRequest) / 4 + @intCast(u16, values.len),
        .cid = xid,
        .drawable = root,
        .mask = mask,
    };

    try connection.send(request);
    for (values) |val| {
        try connection.send(val);
    }

    return xid;
}
