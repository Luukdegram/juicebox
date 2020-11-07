/// Constants that belong to the X protocol
pub const Values = struct {
    pub const GC_FOREGROUND = 4;
    pub const GC_BACKGROUND = 8;
    pub const GC_GRAPHICS_EXPOSURES = 65536;
    pub const GX_COPY = 3;
    pub const BACK_PIXEL = 2;
    pub const EVENT_MASK = 2048;
    pub const KEY_PRESS = 2;
    pub const KEY_RELEASE = 3;
    pub const BUTTON_PRESS = 4;
    pub const BUTTON_RELEASE = 5;
};

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
};

pub const SetupRequest = extern struct {
    byte_order: u8,
    pad0: u8,
    major_version: u16,
    minor_version: u16,
    name_len: u16,
    data_len: u16,
    pad1: [2]u8,
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
    length: u16,
    window: XWindow,
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
