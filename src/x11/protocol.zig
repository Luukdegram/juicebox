//! Contains all structs, constants and types that belong
//! to the X11 protocol as well as helper structs/functions
//! to ease the process of working with the X11 protocol

/// All constant that belong to updating Window attributes
pub const WindowAttributes = enum(u32) {
    back_pixmap = 1,
    back_pixel = 2,
    border_pixmap = 4,
    border_pixel = 8,
    bit_gravity = 16,
    win_gravity = 32,
    backing_store = 64,
    backing_planes = 128,
    backing_pixel = 256,
    override_redirect = 512,
    save_under = 1024,
    event_mask = 2048,
    dont_propagate = 4096,
    colormap = 8192,
    cursor = 16348,

    pub fn toInt(self: WindowAttributes) u32 {
        return @enumToInt(self);
    }
};

pub const WindowConfigMask = packed struct {
    x: bool = false,
    y: bool = false,
    width: bool = false,
    height: bool = false,
    border_width: bool = false,
    sibling: bool = false,
    stack_mode: bool = false,
    pad: u9 = 0,

    pub fn toInt(self: WindowConfigMask) u16 {
        return @bitCast(u16, self);
    }
};

// Ensure that our mask structs have the correct size
comptime {
    @import("std").debug.assert(@sizeOf(WindowConfigMask) == 2);
}

pub const WindowChanges = struct {
    x: i16 = 0,
    y: i16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    border_width: u16 = 0,
    sibling: Types.Window = 0,
    stack_mode: u8 = 0,
};

/// Determines the length of values to be given depending on the given mask
pub fn maskLen(mask: anytype) u16 {
    const std = @import("std");
    const T = @TypeOf(mask);
    std.debug.assert(@typeInfo(T) == .Struct);

    var len: u16 = 0;
    inline for (std.meta.fields(T)) |field| {
        if (field.field_type == bool and @field(mask, field.name)) len += 1;
    }
    return len;
}

/// X Protocol Types, makes it easier to read data
pub const Types = struct {
    pub const Keycode = u8;
    pub const VisualId = u32;
    pub const Window = u32;
    pub const GContext = u32;
    pub const Drawable = u32;
    pub const Pixmap = u32;
    pub const Font = u32;
    pub const Bool32 = u32;
    pub const Atom = u32;
    pub const Colormap = u32;
    pub const Cursor = u32;
    pub const Keysym = u32;
};

/// Predefined Atoms. Those are Atoms with a set value, all other Atoms
/// must be retrieved by name from X11
pub const Atoms = enum(u32) {
    none_or_any = 0,
    primary = 1,
    secondary = 2,
    arc = 3,
    atom = 4,
    bitmap = 5,
    cardinal = 6,
    colormap = 7,
    cursor = 8,
    cut_buffer_0 = 9,
    cut_buffer_1 = 10,
    cut_buffer_2 = 11,
    cut_buffer_3 = 12,
    cut_buffer_4 = 13,
    cut_buffer_5 = 14,
    cut_buffer_6 = 15,
    cut_buffer_7 = 16,
    drawable = 17,
    font = 18,
    integer = 19,
    pixmap = 20,
    point = 21,
    rectangle = 22,
    resource_manager = 23,
    rgb_color_map = 24,
    rgb_best_map = 25,
    rgb_blue_map = 26,
    rgb_default_map = 27,
    rgb_gray_map = 28,
    rgb_green_map = 29,
    rgb_red_map = 30,
    string = 31,
    visual_id = 32,
    window = 33,
    wm_command = 34,
    wm_hints = 35,
    wm_client_machine = 36,
    wm_icon_name = 37,
    wm_icon_size = 38,
    wm_name = 39,
    wm_normal_hints = 40,
    wm_size_hints = 41,
    wm_zoom_hints = 42,
    min_space = 43,
    norm_space = 44,
    max_space = 45,
    end_space = 46,
    superscript_x = 47,
    superscript_y = 48,
    subscript_x = 49,
    subscript_y = 50,
    underline_position = 51,
    underline_tickness = 52,
    strikout_ascent = 53,
    strikout_descent = 54,
    italic_angle = 55,
    x_height = 56,
    quad_width = 57,
    weight = 58,
    point_size = 59,
    resolution = 60,
    copyright = 61,
    notice = 62,
    font_name = 63,
    family_name = 64,
    full_name = 65,
    cap_height = 66,
    wm_class = 67,
    wm_transient_for = 68,

    /// Retrurns the value of the given atom as u32
    pub fn toInt(self: Atoms) u32 {
        return @enumToInt(self);
    }
};

/// Contains the mask and its value
pub const ValueMask = struct {
    mask: WindowAttributes,
    value: u32,
};

pub const SetupRequest = extern struct {
    byte_order: u8 = if (@import("std").builtin.target.cpu.arch.endian() == .Big) 0x42 else 0x6c,
    pad0: u8 = 0,
    major_version: u16 = 11,
    minor_version: u16 = 0,
    name_len: u16,
    data_len: u16,
    pad1: [2]u8 = [_]u8{ 0, 0 },
};

pub const Setup = extern struct {
    release_number: u32,
    resource_id_base: u32,
    resource_id_mask: u32,
    motion_buffer_size: u32,
    vendor_len: u16,
    maximum_request_length: u16,
    roots_len: u8,
    pixmap_formats_len: u8,
    image_byte_order: u8,
    bitmap_format_bit_order: u8,
    bitmap_format_scanline_unit: u8,
    bitmap_format_scanline_pad: u8,
    min_keycode: Types.Keycode,
    max_keycode: Types.Keycode,
    pad1: [4]u8,
};

pub const IdRangeRequest = extern struct {
    major_opcode: u8 = 136,
    minor_opcode: u8 = 1,
    length: u16 = 1,
};

pub const MapWindowRequest = extern struct {
    major_opcode: u8 = 8,
    pad0: u8 = 0,
    length: u16 = @sizeOf(MapWindowRequest) / 4,
    window: Types.Window,
};
pub const Format = extern struct {
    depth: u8,
    bits_per_pixel: u8,
    scanline_pad: u8,
    pad0: [5]u8,
};
pub const Screen = extern struct {
    root: Types.Window,
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
    root_visual: Types.VisualId,
    backing_store: u8,
    save_unders: u8,
    root_depth: u8,
    allowed_depths_len: u8,
};
pub const Depth = extern struct {
    depth: u8,
    pad0: u8,
    visuals_len: u16,
    pad1: [4]u8,
};
pub const VisualType = extern struct {
    visual_id: Types.VisualId,
    class: u8,
    bits_per_rgb_value: u8,
    colormap_entries: u16,
    red_mask: u32,
    green_mask: u32,
    blue_mask: u32,
    pad0: [4]u8,
};
pub const ValueError = extern struct {
    response_type: u8,
    error_code: u8,
    sequence: u16,
    bad_value: u32,
    minor_opcode: u16,
    major_opcode: u8,
    pad0: [21]u8,
};
pub const IdRangeReply = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    length: u32,
    start_id: u32,
    count: u32,
    pad1: [16]u8,
};
pub const QueryExtensionRequest = extern struct {
    major_opcode: u8 = 98,
    pad0: u8 = 0,
    length: u16,
    name_len: u16,
    pad1: [2]u8 = [_]u8{ 0, 0 },
};
pub const QueryExtensionReply = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    length: u32,
    present: u8,
    major_opcode: u8,
    first_event: u8,
    first_error: u8,
    pad1: [20]u8,
};

pub const CreateWindowRequest = extern struct {
    major_opcode: u8 = 1,
    depth: u8 = 0,
    length: u16,
    wid: Types.Window,
    parent: Types.Window,
    x: i16 = 0,
    y: i16 = 0,
    width: u16,
    height: u16,
    border_width: u16 = 0,
    class: u16 = 0,
    visual: Types.VisualId,
    value_mask: u32,
};
pub const CreateGCRequest = extern struct {
    major_opcode: u8 = 55,
    pad0: u8 = 0,
    length: u16,
    cid: Types.GContext,
    drawable: Types.Drawable,
    mask: u32,
};

pub const ChangePropertyRequest = extern struct {
    major_opcode: u8 = 18,
    mode: u8,
    length: u16,
    window: Types.Window,
    property: Types.Atom,
    prop_type: Types.Atom,
    format: u8 = 8, // by default we make our slices into bytes
    pad0: [3]u8 = [_]u8{0} ** 3,
    data_len: u32,
};

pub const ChangeWindowAttributes = extern struct {
    major_opcode: u8 = 2,
    pad0: u8 = 0,
    length: u16,
    window: Types.Window,
    mask: u32,
};

pub const GrabButtonRequest = extern struct {
    major_opcode: u8 = 28,
    owner_events: u8,
    length: u16 = @sizeOf(GrabButtonRequest) / 4, // 6
    grab_window: Types.Window,
    event_mask: u16,
    pointer_mode: u8,
    keyboard_mode: u8,
    confine_to: Types.Window,
    cursor: Types.Cursor,
    button: u8,
    pad0: u8 = 0,
    modifiers: u16,
};

pub const UngrabButtonRequest = extern struct {
    major_opcode: u8 = 29,
    button: u8,
    length: u16 = @sizeOf(UngrabButtonRequest) / 4, // 3
    window: Types.Window,
    modifiers: u16,
};

pub const GrabKeyRequest = extern struct {
    major_opcode: u8 = 33,
    owner_events: u8,
    length: u16 = @sizeOf(GrabKeyRequest) / 4, // 4
    grab_window: Types.Window,
    modifiers: u16,
    key: Types.Keycode,
    pointer_mode: u8,
    keyboard_mode: u8,
    pad: [3]u8 = [_]u8{0} ** 3,
};

pub const UngrabKeyRequest = extern struct {
    major_opcode: u8 = 34,
    key: Types.Keycode,
    length: u16 = @sizeOf(UngrabKeyRequest) / 4, // 3
    window: Types.Window,
    modifiers: u16,
};

pub const ConfigureWindowRequest = extern struct {
    major_opcode: u8 = 12,
    pad: u8 = 0,
    length: u16,
    window: Types.Window,
    mask: u16,
    pad1: [2]u8 = [_]u8{ 0, 0 },
};

pub const KillClientRequest = extern struct {
    major_opcode: u8 = 113,
    pad: u8 = 0,
    length: u16 = @sizeOf(KillClientRequest) / 4, //2
    window: Types.Window,
};

pub const KeyboardMappingRequest = extern struct {
    major_opcode: u8 = 101,
    pad: u8 = 0,
    length: u16 = @sizeOf(KeyboardMappingRequest) / 4,
    first_keycode: Types.Keycode,
    count: u8,
    pad1: [2]u8 = [_]u8{ 0, 0 },
};

pub const KeyboardMappingReply = extern struct {
    response_type: u8,
    keysyms_per_keycode: u8,
    sequence: u16,
    length: u32,
    pad: [24]u8,
};

pub const SetInputFocusRequest = extern struct {
    major_opcode: u8 = 42,
    revert_to: u8,
    length: u16 = @sizeOf(SetInputFocusRequest) / 4,
    window: Types.Window,
    time_stamp: u32,
};

pub const AtomRequest = extern struct {
    major_opcode: u8 = 16,
    only_if_exists: u8 = 0,
    length: u16,
    name_length: u16,
    pad: u16 = 0,
};

pub const AtomReply = extern struct {
    reply: u8,
    pad: u8,
    sequence: u16,
    length: u32,
    /// 0 = None
    atom: u32,
    pad1: [20]u8,
};
