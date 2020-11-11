const std = @import("std");
const mem = std.mem;

usingnamespace @import("protocol.zig");

//! Contains all the errors generated by the X11 server
//! Given a slice of bytes, creates the correct error type

/// Error type is an error triggered by providing an invalid request,
/// Such as assigning the same event to multiple windows.
pub const ErrorType = extern enum(u8) {
    request = 1,
    value = 2,
    window = 3,
    pixmap = 4,
    atom = 5,
    cursor = 6,
    font = 7,
    match = 8,
    drawable = 9,
    access = 10,
    alloc = 11,
    colormap = 12,
    graphic_context = 13,
    id_choice = 14,
    name = 15,
    length = 16,
    implementation = 17,
};

/// Event represents an X11 event received by the server.
/// The type of the Event is bassed on the `EventType` and requires a switch
/// to identify the correct type.
pub const Error = extern struct {
    /// Always 0 because it's an error
    error_byte: u8 = 0,
    /// The type of error
    code: ErrorType,
    /// The sequence it occured
    sequence: u16,
    /// The resource that was incorrect
    /// This value is unused in certain cases
    resource: u32,
    /// The minor opcode of the request that was incorrect
    minor: u16,
    /// The major opcode of the invalid request
    major: u8,
    /// Unused bytes
    pad: [21]u8 = [_]u8{0} ** 21,

    /// Creates an `Error` union from the given bytes and
    /// asserts the first byte value is 0.
    /// Note: The Event is copied from the bytes and does not own its memory
    pub fn fromBytes(bytes: [32]u8) Error {
        const response_type = bytes[0];
        std.debug.assert(response_type == 0);

        const error_type = @intToEnum(ErrorType, bytes[1]);

        return std.mem.bytesToValue(Error, &bytes);
    }
};

test "Create Dynamic Error" {
    const value_error = Error{
        .code = .value,
        .sequence = 1,
        .resource = 0,
        .minor = 1,
        .major = 2,
    };

    var bytes: [32]u8 = undefined;
    bytes = mem.toBytes(value_error);
    const generated_error = Error.fromBytes(bytes);

    std.testing.expect(std.meta.eql(value_error, generated_error));
}
