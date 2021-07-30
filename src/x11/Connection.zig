//! Connection holds a socket connection to X11 and allows to write
//! and read requests to/from X11. It also contains the authentication with the protocol
const std = @import("std");
const protocol = @import("protocol.zig");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const os = std.os;
const fs = std.fs;

const Connection = @This();

/// Handle to the socket of the X connection
stream: std.net.Stream,
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
    min_keycode: u8,
    max_keycode: u8,
};

/// Connection status
const Status = enum {
    ok,
    authenticate,
    setup_failed,
};

/// xid is used to store the last generated xid which
/// is needed to generate the next one
var xid: Xid = undefined;

/// Xid is used to generate new unique id's needed to build new components
const Xid = struct {
    last: u32,
    max: u32,
    base: u32,
    inc: u32,

    fn init(connection: Connection) Xid {
        // we could use @setRuntimeSafety(false) in this case
        const inc: i32 = @bitCast(i32, connection.setup.mask) &
            -@bitCast(i32, connection.setup.mask);
        return Xid{
            .last = 0,
            .max = 0,
            .base = connection.setup.base,
            .inc = @bitCast(u32, inc),
        };
    }
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

/// Generates a new XID
pub fn genXid(self: *Connection) !u32 {
    var ret: u32 = 0;
    if (self.status != .ok) {
        return error.InvalidConnection;
    }

    const temp = xid.max -% xid.inc;
    if (xid.last >= temp) {
        if (xid.last == 0) {
            xid.max = self.setup.mask;
        } else {
            if (!try self.supportsExtension("XC-MISC")) {
                return error.MiscUnsupported;
            }

            try self.send(protocol.IdRangeRequest{});

            const reply = try self.recv(protocol.IdRangeReply);

            xid.last = reply.start_id;
            xid.max = reply.start_id + (reply.count - 1) * xid.inc;
        }
    } else {
        xid.last += xid.inc;
    }
    ret = xid.last | xid.base;
    return ret;
}

/// Same error set as std.fs.File
const ReadError = error{
    InputOutput,
    SystemResources,
    IsDir,
    OperationAborted,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,

    /// This error occurs when no global event loop is configured,
    /// and reading from the file descriptor would block.
    WouldBlock,

    /// In WASI, this error occurs when the file descriptor does
    /// not hold the required rights to read from it.
    AccessDenied,
    Unexpected,
};

/// Returns a `std.io.Reader` to the connection's socket reader
pub fn reader(self: *Connection) std.io.Reader(*Connection, ReadError, read) {
    return .{ .context = self };
}

fn read(self: *Connection, buffer: []u8) ReadError!usize {
    return std.os.read(self.stream.handle, buffer);
}

/// Sends data to the X11 server
/// TODO: Buffer all requests and allow the user to flush them at once
/// for better performance, and easier counting of total request size
pub fn send(self: *const Connection, data: anytype) !void {
    if (@TypeOf(data) == []const u8 or @TypeOf(data) == []u8) {
        try self.stream.writer().writeAll(data);
    } else {
        try self.stream.writer().writeAll(mem.asBytes(&data));
    }
}

/// Reads the given type from the X11 server
pub fn recv(self: *Connection, comptime T: type) !T {
    return self.reader().readStruct(T);
}

/// Disconnects from X and frees all memory
pub fn deinit(self: *Connection) void {
    self.gpa.free(self.formats);
    for (self.screens) |screen| {
        for (screen.depths) |depth| self.gpa.free(depth.visual_types);
        self.gpa.free(screen.depths);
    }
    self.gpa.free(self.screens);
    self.stream.close();
}

/// Gets a named Atom from the X11 server
pub fn getAtom(self: *Connection, name: []const u8) !protocol.Types.Atom {
    const padding = &[_]u8{0} ** 3; //max size of xpad = 3
    const request = protocol.AtomRequest{
        .length = @intCast(u16, 2 + (name.len + xpad(name.len)) / 4),
        .name_length = @intCast(u16, name.len),
    };

    try self.send(request);
    try self.send(name);
    try self.send(padding[0..xpad(name.len)]);

    const reply = try self.recv(protocol.AtomReply);
    return reply.atom;
}

/// Checks if the X11 server supports the given extension or: not
fn supportsExtension(self: *Connection, ext_name: []const u8) !bool {
    const request = protocol.QueryExtensionRequest{
        .length = @intCast(u16, @sizeOf(protocol.QueryExtensionRequest) + ext_name.len + xpad(ext_name.len)) / 4,
        .name_len = @intCast(u16, ext_name.len),
    };
    try self.send(request);
    try self.send(ext_name);
    try self.send(request.pad1);

    const reply = try self.stream.reader().readStruct(protocol.QueryExtensionReply);

    return reply.present != 0;
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
    const stream = if (display.host.len != 0) blk: {
        const port: u16 = 6000 + @intCast(u16, display.display);
        const address = try std.net.Address.parseIp(display.host, port);
        break :blk try std.net.tcpConnectToAddress(address);
    } else blk: {
        var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
        const socket_path = std.fmt.bufPrint(path_buf[0..], "/tmp/.X11-unix/X{}", .{display.display}) catch unreachable;
        break :blk try std.net.connectUnixSocket(socket_path);
    };

    errdefer stream.close();

    var auth = authenticate(gpa) catch |e| switch (e) {
        error.WouldBlock => unreachable,
        error.OperationAborted => unreachable,
        else => return ConnectionError.ConnectionFailed,
    };
    defer auth.deinit(gpa);

    return connect(gpa, stream, auth) catch |err| switch (err) {
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
fn authenticate(gpa: *Allocator) !Auth {
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
fn connect(gpa: *Allocator, stream: std.net.Stream, auth: Auth) !Connection {
    var conn = Connection{
        .stream = stream,
        .gpa = gpa,
        .setup = undefined,
        .formats = undefined,
        .screens = undefined,
        .status = .authenticate,
    };

    try conn.writeSetup(auth);
    try conn.readSetup();
    if (conn.status == .ok) {
        // set the initial xid generator
        xid = Xid.init(conn);
    }

    return conn;
}

/// Writes to the stream to ask for the display setup
fn writeSetup(self: *Connection, auth: Auth) !void {
    const pad = [3]u8{ 0, 0, 0 };
    try self.send(protocol.SetupRequest{
        .name_len = @intCast(u16, auth.name.len),
        .data_len = @intCast(u16, auth.data.len),
    });
    try self.send(auth.name);
    try self.send(pad[0..xpad(auth.name.len)]);
    try self.send(auth.data);
    try self.send(pad[0..xpad(auth.data.len)]);
}

/// Reads the setup response from the connection which is then parsed and saved in the connection
fn readSetup(self: *Connection) !void {
    const stream = self.reader();

    const SetupGeneric = extern struct {
        status: u8,
        pad0: [5]u8,
        length: u16,
    };
    const header = try stream.readStruct(SetupGeneric);

    const setup_buffer = try self.gpa.alloc(u8, header.length * 4);
    errdefer self.gpa.free(setup_buffer);

    try stream.readNoEof(setup_buffer);

    self.status = switch (header.status) {
        0 => .setup_failed,
        1 => .ok,
        2 => .authenticate,
        else => return error.InvalidStatus,
    };

    if (self.status == .ok) {
        try self.parseSetup(setup_buffer);
    }
}

/// Parses the setup received from the connection into
/// seperate struct types
fn parseSetup(self: *Connection, buffer: []u8) !void {
    const allocator = self.gpa;

    var setup: protocol.Setup = undefined;
    var index: usize = parseSetupType(&setup, buffer[0..]);

    self.setup = Connection.Setup{
        .base = setup.resource_id_base,
        .mask = setup.resource_id_mask,
        .min_keycode = setup.min_keycode,
        .max_keycode = setup.max_keycode,
    };

    // ignore the vendor for now
    const vendor = buffer[index .. index + setup.vendor_len];
    index += vendor.len;

    const formats = try allocator.alloc(Format, setup.pixmap_formats_len);
    errdefer allocator.free(formats);
    for (formats) |*f| {
        var format: protocol.Format = undefined;
        index += parseSetupType(&format, buffer[index..]);
        f.* = .{
            .depth = format.depth,
            .bits_per_pixel = format.bits_per_pixel,
            .scanline_pad = format.scanline_pad,
        };
    }

    const screens = try allocator.alloc(Screen, setup.roots_len);
    errdefer allocator.free(screens);
    for (screens) |*s| {
        var screen: protocol.Screen = undefined;
        index += parseSetupType(&screen, buffer[index..]);

        const depths = try allocator.alloc(Depth, screen.allowed_depths_len);
        errdefer allocator.free(depths);
        for (depths) |*d| {
            var depth: protocol.Depth = undefined;
            index += parseSetupType(&depth, buffer[index..]);

            const visual_types = try allocator.alloc(VisualType, depth.visuals_len);
            errdefer allocator.free(visual_types);
            for (visual_types) |*t| {
                var visual_type: protocol.VisualType = undefined;
                index += parseSetupType(&visual_type, buffer[index..]);
                t.* = .{
                    .id = visual_type.visual_id,
                    .bits_per_rgb_value = visual_type.bits_per_rgb_value,
                    .colormap_entries = visual_type.colormap_entries,
                    .red_mask = visual_type.red_mask,
                    .green_mask = visual_type.green_mask,
                    .blue_mask = visual_type.blue_mask,
                };
            }

            d.* = .{
                .depth = depth.depth,
                .visual_types = visual_types,
            };
        }

        s.* = .{
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
            .depths = depths,
        };
    }

    if (index != buffer.len) {
        return error.IncorrectSetup;
    }

    self.formats = formats;
    self.screens = screens;
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
pub const Screen = struct {
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
