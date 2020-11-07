const std = @import("std");
const protocol = @import("protocol.zig");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const os = std.os;
const fs = std.fs;

pub const Connection = @This();

/// Handle to the socket of the X connection
handle: fs.File,
/// Allocator used to allocate setup data
gpa: *Allocator,
/// setup information such as base and mask. Needed to generate Xid's
setup: Setup,
/// supported formats by the server
formats: []Format,
/// list of screens the user has connected (monitors)
screens: []Screen,
/// Connection status
status: Status,

/// Errors that can occur when attempting to establish an X11 connection
const ConnectionError = error{
    /// Environment variable "DISPLAY" is missing
    DisplayNotFound,
    /// Out of memory
    OutOfMemory,
    /// Triggered when we cannot parse the DISPLAY variable
    InvalidDisplayFormat,
    /// When no connection can be made with the X server
    ConnectionFailed,
};

/// Errors that can occur when parsing display name
const ParseError = error{
    MissingColon,
    MissingDisplayIndex,

    // from std.fmt.parseInt
    Overflow,
    InvalidCharacter,
};

/// Base Setup information
const Setup = struct {
    base: u32,
    mask: u32,
};

/// Connection status
const Status = enum {
    ok,
    authenticating,
    setup_failed,
};

/// Initializes a new connection with the X11 server and returns a handle
/// to it as well as the setup of the display
pub fn init(gpa: *Allocator) ConnectionError!Connection {
    const display_name = os.getenv("DISPLAY");

    if (display_name) |name|
        return openDisplay(gpa, name) catch |err| switch (err) {
            error.InvalidDisplayFormat => ConnectionError.InvalidDisplayFormat,
            else => ConnectionError.ConnectionFailed,
        };

    return ConnectionError.DisplayNotFound;
}

/// Struct containing the pieces of a parsed display
const ParsedDisplay = struct {
    /// host to the display
    host: []const u8,
    /// protocol used (TCP)
    protocol: []const u8,
    /// Index of display
    display: u32,
    /// The screen
    screen: u32,
};

/// Parses the given name to determine how to connect to the X11 server
fn parseDisplay(name: []const u8) ParseError!ParsedDisplay {
    var result = ParsedDisplay{
        .host = undefined,
        .protocol = name[0..0],
        .display = undefined,
        .screen = undefined,
    };
    const after_prot = if (mem.lastIndexOfScalar(u8, name, '/')) |pos| blk: {
        result.protocol = name[0..pos];
        break :blk name[pos..];
    } else name;

    const colon = mem.lastIndexOfScalar(u8, after_prot, ':') orelse return ParseError.MissingColon;
    var it = mem.split(after_prot[colon + 1 ..], ".");
    result.display = try std.fmt.parseInt(u32, it.next() orelse return ParseError.MissingDisplayIndex, 10);
    result.screen = if (it.next()) |s| try std.fmt.parseInt(u32, s, 10) else 0;
    result.host = after_prot[0..colon];
    return result;
}

/// Parses the display name and opens the connection
fn openDisplay(gpa: *Allocator, name: []const u8) !Connection {
    const display = parseDisplay(name) catch return ConnectionError.InvalidDisplayFormat;

    if (display.protocol.len != 0 and !mem.eql(u8, display.protocol, "unix")) {
        return ConnectionError.ConnectionFailed;
    }

    // open connection to host if set, else connect with unix socket
    const file = if (display.host.len != 0) blk: {
        const port: u16 = 6000 + @intCast(u16, display.display);
        const address = try std.net.Address.parseIp(display.host, port);
        break :blk try std.net.tcpConnectToAddress(address);
    } else blk: {
        var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
        const socket_path = std.fmt.bufPrint(path_buf[0..], "/tmp/.X11-unix/X{}", .{display.display}) catch unreachable;
        break :blk try std.net.connectUnixSocket(socket_path);
    };

    errdefer file.close();

    var auth = authenticate(gpa, file, display.display) catch |e| switch (e) {
        error.WouldBlock => unreachable,
        error.OperationAborted => unreachable,
        else => return ConnectionError.ConnectionFailed,
    };
    defer auth.deinit(gpa);

    return connect(gpa, file, auth) catch |err| switch (err) {
        error.WouldBlock => unreachable,
        error.OperationAborted => unreachable,
        error.DiskQuota => unreachable,
        error.FileTooBig => unreachable,
        error.NoSpaceLeft => unreachable,
        else => ConnectionError.ConnectionFailed,
    };
}

/// Struct that contains all authentication data
/// read from the connection stream
const Auth = struct {
    family: u16,
    address: []u8,
    number: []u8,
    name: []u8,
    data: []u8,

    /// Frees all authentication data at once
    fn deinit(self: *Auth, gpa: *Allocator) void {
        gpa.free(self.address);
        gpa.free(self.number);
        gpa.free(self.name);
        gpa.free(self.data);
        self.* = undefined;
    }
};

/// Authenticates with the X11 server by retrieving the authentication
/// details from the environment
fn authenticate(gpa: *Allocator, sock: fs.File, display: u32) !Auth {
    const xau_file = if (os.getenv("XAUTHORITY")) |xau_file_name| blk: {
        break :blk try fs.openFileAbsolute(xau_file_name, .{});
    } else blk: {
        const home = os.getenv("HOME") orelse return error.HomeDirectoryNotFound;
        var dir = try fs.cwd().openDir(home, .{});
        defer dir.close();

        break :blk try dir.openFile(".Xauthority", .{});
    };
    defer xau_file.close();

    const stream = &xau_file.reader();

    var hostname_buf: [os.HOST_NAME_MAX]u8 = undefined;
    const hostname = try os.gethostname(&hostname_buf);

    while (true) {
        var auth = blk: {
            const family = try stream.readIntBig(u16);
            const address = try readString(gpa, stream);
            errdefer gpa.free(address);
            const number = try readString(gpa, stream);
            errdefer gpa.free(number);
            const name = try readString(gpa, stream);
            errdefer gpa.free(name);
            const data = try readString(gpa, stream);
            errdefer gpa.free(data);

            break :blk Auth{
                .family = family,
                .address = address,
                .number = number,
                .name = name,
                .data = data,
            };
        };
        if (mem.eql(u8, hostname, auth.address)) {
            return auth;
        } else {
            auth.deinit(gpa);
            continue;
        }
    }

    return error.AuthNotFound;
}

/// creates a new `Connection` and writes the screen setup to the server
/// and then reads and parses it from the response
fn connect(gpa: *Allocator, file: fs.File, auth: Auth) !Connection {
    var conn = Connection{
        .handle = file,
        .gpa = gpa,
        .setup = undefined,
        .formats = undefined,
        .screens = undefined,
        .status = .authenticating,
    };

    try writeSetup(file, auth);
    try readSetup(gpa, &conn);
    if (conn.status == .ok) {
        //conn.xid = Connection.Xid.init(conn);
    }

    return conn;
}

/// Writes to the stream to ask for the display setup
fn writeSetup(file: fs.File, auth: Auth) fs.File.WriteError!void {
    const pad = [3]u8{ 0, 0, 0 };
    var parts: [6]os.iovec_const = undefined;
    var parts_index: usize = 0;
    var setup_req = protocol.SetupRequest{
        .byte_order = if (std.builtin.endian == .Big) 0x42 else 0x6c,
        .pad0 = 0,
        .major_version = 11,
        .minor_version = 0,
        .name_len = 0,
        .data_len = 0,
        .pad1 = [2]u8{ 0, 0 },
    };
    parts[parts_index].iov_len = @sizeOf(protocol.SetupRequest);
    parts[parts_index].iov_base = @ptrCast([*]const u8, &setup_req);
    parts_index += 1;
    comptime std.debug.assert(xpad(@sizeOf(protocol.SetupRequest)) == 0);

    setup_req.name_len = @intCast(u16, auth.name.len);
    parts[parts_index].iov_len = auth.name.len;
    parts[parts_index].iov_base = auth.name.ptr;
    parts_index += 1;
    parts[parts_index].iov_len = xpad(auth.name.len);
    parts[parts_index].iov_base = &pad;
    parts_index += 1;

    setup_req.data_len = @intCast(u16, auth.data.len);
    parts[parts_index].iov_len = auth.data.len;
    parts[parts_index].iov_base = auth.data.ptr;
    parts_index += 1;
    parts[parts_index].iov_len = xpad(auth.data.len);
    parts[parts_index].iov_base = &pad;
    parts_index += 1;

    std.debug.assert(parts_index <= parts.len);

    return file.writevAll(parts[0..parts_index]);
}

/// Reads the setup response from the connection which is then parsed and saved in the connection
fn readSetup(gpa: *Allocator, connection: *Connection) !void {
    const stream = connection.handle.reader();

    const SetupGeneric = extern struct {
        status: u8,
        pad0: [5]u8,
        length: u16,
    };
    const header = try stream.readStruct(SetupGeneric);

    const setup_buffer = try gpa.alloc(u8, header.length * 4);
    errdefer gpa.free(setup_buffer);

    try stream.readNoEof(setup_buffer);

    connection.status = switch (header.status) {
        0 => .setup_failed,
        1 => .ok,
        2 => .authenticating,
        else => return error.InvalidStatus,
    };

    if (connection.status == .ok) {
        try parseSetup(connection, setup_buffer);
    }
}

/// Parses the setup received from the connection into
/// seperate struct types
fn parseSetup(conn: *Connection, buffer: []u8) !void {
    var allocator = conn.gpa;

    var setup: protocol.Setup = undefined;
    var index: usize = parseSetupType(&setup, buffer[0..]);

    conn.setup = Connection.Setup{
        .base = setup.resource_id_base,
        .mask = setup.resource_id_mask,
    };

    // ignore the vendor for now
    const vendor = buffer[index .. index + setup.vendor_len];
    index += vendor.len;

    var formats = std.ArrayList(Format).init(allocator);
    errdefer formats.deinit();
    var format_counter: usize = 0;
    while (format_counter < setup.pixmap_formats_len) : (format_counter += 1) {
        var format: protocol.Format = undefined;
        index += parseSetupType(&format, buffer[index..]);
        try formats.append(.{
            .depth = format.depth,
            .bits_per_pixel = format.bits_per_pixel,
            .scanline_pad = format.scanline_pad,
        });
    }

    var screens = std.ArrayList(Screen).init(allocator);
    errdefer screens.deinit();
    var screen_counter: usize = 0;
    while (screen_counter < setup.roots_len) : (screen_counter += 1) {
        var screen: protocol.Screen = undefined;
        index += parseSetupType(&screen, buffer[index..]);

        var depths = std.ArrayList(Depth).init(allocator);
        errdefer depths.deinit();
        var depth_counter: usize = 0;
        while (depth_counter < screen.allowed_depths_len) : (depth_counter += 1) {
            var depth: protocol.Depth = undefined;
            index += parseSetupType(&depth, buffer[index..]);

            var visual_types = std.ArrayList(VisualType).init(allocator);
            errdefer visual_types.deinit();
            var visual_counter: usize = 0;
            while (visual_counter < depth.visuals_len) : (visual_counter += 1) {
                var visual_type: protocol.VisualType = undefined;
                index += parseSetupType(&visual_type, buffer[index..]);
                try visual_types.append(.{
                    .id = visual_type.visual_id,
                    .bits_per_rgb_value = visual_type.bits_per_rgb_value,
                    .colormap_entries = visual_type.colormap_entries,
                    .red_mask = visual_type.red_mask,
                    .green_mask = visual_type.green_mask,
                    .blue_mask = visual_type.blue_mask,
                });
            }

            try depths.append(.{
                .depth = depth.depth,
                .visual_types = visual_types.toOwnedSlice(),
            });
        }
        try screens.append(.{
            .root = screen.root,
            .default_colormap = screen.default_colormap,
            .white_pixel = screen.white_pixel,
            .black_pixel = screen.black_pixel,
            .current_input_mask = screen.current_input_mask,
            .width_pixel = screen.width_pixel,
            .height_pixel = screen.height_pixel,
            .width_milimeter = screen.width_milimeter,
            .height_milimeter = screen.height_milimeter,
            .min_installed_maps = screen.min_installed_maps,
            .max_installed_maps = screen.max_installed_maps,
            .root_visual = screen.root_visual,
            .backing_store = screen.backing_store,
            .save_unders = screen.save_unders,
            .root_depth = screen.root_depth,
            .depths = depths.toOwnedSlice(),
        });
    }

    if (index != buffer.len) {
        return error.IncorrectSetup;
    }

    conn.formats = formats.toOwnedSlice();
    conn.screens = screens.toOwnedSlice();
}

/// Format represents support pixel formats
const Format = struct {
    depth: u32,
    bits_per_pixel: u8,
    scanline_pad: u8,
};

/// Depth of screen buffer
const Depth = struct {
    depth: u8,
    visual_types: []VisualType,
};

/// Represents the type of the visuals on the screen
const VisualType = struct {
    id: u32,
    bits_per_rgb_value: u8,
    colormap_entries: u16,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
};

/// Screen with its values, each screen has a root id
/// which is unique and is used to create windows on the screen
const Screen = struct {
    root: u32,
    default_colormap: u32,
    white_pixel: u32,
    black_pixel: u32,
    current_input_mask: u32,
    width_pixel: u16,
    height_pixel: u16,
    width_milimeter: u16,
    height_milimeter: u16,
    min_installed_maps: u16,
    max_installed_maps: u16,
    root_visual: u32,
    backing_store: u8,
    save_unders: u8,
    root_depth: u8,
    depths: []Depth,
};

/// Retrieves the wanted type from the buffer and returns its size
fn parseSetupType(wanted: anytype, buffer: []u8) usize {
    std.debug.assert(@typeInfo(@TypeOf(wanted)) == .Pointer);
    const size = @sizeOf(@TypeOf(wanted.*));
    wanted.* = std.mem.bytesToValue(@TypeOf(wanted.*), buffer[0..size]);
    return size;
}

/// First reads the length bytes and then reads that length from the given stream
fn readString(gpa: *Allocator, stream: anytype) ![]u8 {
    const len = try stream.readIntBig(u16);
    const buf = try gpa.alloc(u8, len);
    errdefer gpa.free(buf);

    try stream.readNoEof(buf);
    return buf;
}

fn xpad(n: usize) usize {
    return @bitCast(usize, (-%@bitCast(isize, n)) & 3);
}
