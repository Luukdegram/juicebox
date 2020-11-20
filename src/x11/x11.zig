//! Entry point to the X11 library
//! This library does not follow a design such as XCB or libX.
//! Note that this library is also designed for Juicebox, but may
//! be used for external sources as well.

pub const Window = @import("Window.zig");
pub const Connection = @import("Connection.zig");
pub const Context = @import("Context.zig");
pub const events = @import("events.zig");
pub const protocol = @import("protocol.zig");
pub const input = @import("input.zig");
pub const errors = @import("errors.zig");
pub const keys = @import("keys.zig");
