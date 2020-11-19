const Connection = @import("Connection.zig");
const Window = @import("Window.zig");
const EventMask = @import("events.zig").Mask;

usingnamespace @import("protocol.zig");
usingnamespace @import("keys.zig");

pub const Modifiers = packed struct {
    /// Shift keys
    shift: bool = false,
    /// Capslock key
    lock: bool = false,
    /// Control keys
    control: bool = false,
    /// Alt L & R + Meta L
    mod1: bool = false,
    /// Num lock
    mod2: bool = false,
    /// Empty by default
    mod3: bool = false,
    /// Super keys L & R and Hyper L
    mod4: bool = false,
    /// ISO_Level3_Shift and Mode Switch key
    mod5: bool = false,

    padding: u7 = 0,
    any_bit: bool = false,

    pub const any: @This() = .{ .any_bit = true };

    pub fn toInt(self: @This()) u16 {
        return @bitCast(u16, self);
    }
};

comptime {
    @import("std").debug.assert(@sizeOf(Modifiers) == 2);
}

/// Options to set when grabbing a button
pub const GrabButtonOptions = struct {
    owner_events: bool = false,
    /// which pointer events to grab
    event_mask: EventMask = .{},
    /// How events are triggered. Async by default
    pointer_mode: GrabMode = .@"async",
    /// How events are triggered. Async by default
    keyboard_mode: GrabMode = .@"async",
    /// The window that owns the grab
    grab_window: Window,
    /// The window where the events are sent to
    confine_to: Window,
    /// Which cursor to show, 0 (none) by default
    cursor: Types.Cursor = 0,
    /// Which button to grab
    button: u8,
    /// The modifier required to grab a button
    modifiers: Modifiers,
};

/// Whether the grab mode should be sync -or asynchronous
pub const GrabMode = enum(u8) {
    sync = 0,
    @"async" = 1,
};

/// Grabs a button and binds it to specific windows
pub fn grabButton(conn: *Connection, options: GrabButtonOptions) !void {
    try conn.send(GrabButtonRequest{
        .owner_events = @boolToInt(options.owner_events),
        .grab_window = options.grab_window.handle,
        .event_mask = @truncate(u16, options.event_mask.toInt()),
        .pointer_mode = @enumToInt(options.pointer_mode),
        .keyboard_mode = @enumToInt(options.keyboard_mode),
        .confine_to = options.confine_to.handle,
        .cursor = options.cursor,
        .button = options.button,
        .modifiers = options.modifiers.toInt(),
    });
}

/// Ungrabs a button and its modifiers. Use 0 for `button` to ungrab all buttons
pub fn ungrabButton(conn: *Connection, button: u8, window: Window, modifiers: Modifiers) !void {
    try conn.send(UngrabButtonRequest{
        .button = button,
        .window = window.handle,
        .modifiers = modifiers.toInt(),
    });
}

/// The options to grab a specific key
pub const GrabKeyOptions = struct {
    /// Is owner of events
    owner_events: bool = false,
    /// Window that will recieve events for those keys
    grab_window: Window,
    /// Which modifier keys to be used
    modifiers: Modifiers,
    /// The actual key to grab
    key_code: Types.Keycode,
    /// How the pointer events are triggered
    pointer_mode: GrabMode = .@"async",
    /// How the keyboard events are triggered
    keyboard_mode: GrabMode = .@"async",
};

/// Grabs a key with optional modifiers for the given window
pub fn grabKey(conn: *Connection, options: GrabKeyOptions) !void {
    try conn.send(GrabKeyRequest{
        .owner_events = @boolToInt(options.owner_events),
        .grab_window = options.grab_window.handle,
        .modifiers = options.modifiers.toInt(),
        .key = options.key_code,
        .pointer_mode = @enumToInt(options.pointer_mode),
        .keyboard_mode = @enumToInt(options.keyboard_mode),
    });
}

/// Ungrabs the key and its modifiers for the specified window
pub fn ungrabKey(conn: *Connection, key: Types.Keycode, window: Window, modifiers: Modifiers) !void {
    try conn.send(UngrabKeyRequest{
        .key = key,
        .window = window.handle,
        .modifiers = modifiers.toInt(),
    });
}

/// Table containing a list of `Types.keysym`
/// can be retrieved from a connection
pub const KeysymTable = struct {
    list: []Types.Keysym,
    keysyms_per_keycode: u8,
    min_keycode: u8,
    max_keycode: u8,

    /// No Symbol (returned when a given keysym cannot be found)
    pub const no_symbol: u32 = 0x000;

    /// Returns the keymapping of user's keyboard
    pub fn init(con: *Connection) !KeysymTable {
        const count = con.setup.max_keycode - con.setup.min_keycode + 1;
        try con.send(KeyboardMappingRequest{
            .first_keycode = con.setup.min_keycode,
            .count = count,
        });

        const reply = try con.recv(KeyboardMappingReply);

        const keysyms = try con.gpa.alloc(Types.Keysym, reply.length);
        for (keysyms) |*keysym| {
            keysym.* = try con.reader().readIntNative(Types.Keysym);
        }

        return KeysymTable{
            .list = keysyms,
            .keysyms_per_keycode = reply.keysyms_per_keycode,
            .min_keycode = con.setup.min_keycode,
            .max_keycode = con.setup.max_keycode,
        };
    }

    /// Converts a keysym to a keycode
    pub fn keysymToKeycode(self: KeysymTable, keysym: Types.Keysym) Types.Keycode {
        var outer: u8 = 0;
        while (outer < self.keysyms_per_keycode) : (outer += 1) {
            var i: u8 = self.min_keycode;
            while (i < self.max_keycode) : (i += 1) if (self.keysymAtCol(i, outer) == keysym) return i;
        }
        return 0;
    }

    /// Finds a `Types.keysym` for the given `col` and `keycode`
    fn keysymAtCol(self: KeysymTable, keycode: Types.Keycode, col: u8) Types.Keysym {
        if ((col >= self.keysyms_per_keycode and col > 3) or
            keycode < self.min_keycode or
            keycode > self.max_keycode)
            return no_symbol;

        var per: u32 = self.keysyms_per_keycode;
        var mut_col = col;
        const start: usize = (keycode - self.min_keycode) * per;
        const keysyms = self.list[start .. start + per];
        if (col < 4) {
            if (col > 1) {
                while (per > 2 and keysyms[per - 1] == no_symbol)
                    per -= 1;

                if (per < 3)
                    mut_col -= 2;
            }

            if (per <= mut_col | 1 or keysyms[mut_col | 1] == no_symbol) {
                var lower: Types.Keysym = undefined;
                var upper: Types.Keysym = undefined;
                convertCase(keysyms[mut_col & ~@as(u32, 1)], &lower, &upper);

                return if (mut_col & 1 == 0)
                    lower
                else if (lower == upper)
                    no_symbol
                else
                    upper;
            }
        }

        return keysyms[mut_col];
    }

    /// Converts a keycode to a keysym
    pub fn keycodeToKeysym(self: KeysymTable, keycode: Types.Keycode) Types.Keysym {
        return self.keysymAtCol(keycode, 0);
    }

    /// Frees the keysyms list
    pub fn deinit(self: KeysymTable, alloc: *@import("std").mem.Allocator) void {
        alloc.free(self.list);
    }
};

/// Converts the given `keysym` into a lower and upper `Types.keysym`
fn convertCase(keysym: Types.Keysym, lower: *Types.Keysym, upper: *Types.Keysym) void {

    // latin 1
    if (keysym < 0x100) return ucsConvertCase(keysym, lower, upper);

    // unicode
    if (keysym & 0xff000000 == 0x01000000) {
        ucsConvertCase(keysym, lower, upper);
        lower.* |= 0x01000000;
        upper.* |= 0x01000000;
        return;
    }

    // legacy keysyms
    lower.* = keysym;
    upper.* = keysym;

    switch (keysym >> 8) {
        // latin 2
        1 => {
            if (keysym == XK_Aogonek)
                lower.* = XK_aogonek
            else if (keysym >= XK_Lstroke and keysym <= XK_Sacute)
                lower.* += (XK_lstroke - XK_Lstroke)
            else if (keysym >= XK_Scaron and keysym <= XK_Zacute)
                lower.* += (XK_scaron - XK_Scaron)
            else if (keysym >= XK_Zcaron and keysym <= XK_Zabovedot)
                lower.* += (XK_zcaron - XK_Zcaron)
            else if (keysym == XK_aogonek)
                upper.* = XK_Aogonek
            else if (keysym >= XK_lstroke and keysym <= XK_sacute)
                upper.* -= (XK_lstroke - XK_Lstroke)
            else if (keysym >= XK_scaron and keysym <= XK_zacute)
                upper.* -= (XK_scaron - XK_Scaron)
            else if (keysym >= XK_zcaron and keysym <= XK_zabovedot)
                upper.* -= (XK_zcaron - XK_Zcaron)
            else if (keysym >= XK_Racute and keysym <= XK_Tcedilla)
                lower.* += (XK_racute - XK_Racute)
            else if (keysym >= XK_racute and keysym <= XK_tcedilla)
                upper.* -= (XK_racute - XK_Racute);
        },
        // latin 3
        2 => {
            if (keysym >= XK_Hstroke and keysym <= XK_Hcircumflex)
                lower.* += (XK_hstroke - XK_Hstroke)
            else if (keysym >= XK_Gbreve and keysym <= XK_Jcircumflex)
                lower.* += (XK_gbreve - XK_Gbreve)
            else if (keysym >= XK_hstroke and keysym <= XK_hcircumflex)
                upper.* -= (XK_hstroke - XK_Hstroke)
            else if (keysym >= XK_gbreve and keysym <= XK_jcircumflex)
                upper.* -= (XK_gbreve - XK_Gbreve)
            else if (keysym >= XK_Cabovedot and keysym <= XK_Scircumflex)
                lower.* += (XK_cabovedot - XK_Cabovedot)
            else if (keysym >= XK_cabovedot and keysym <= XK_scircumflex)
                upper.* -= (XK_cabovedot - XK_Cabovedot);
        },
        // latin 4
        3 => {
            if (keysym >= XK_Rcedilla and keysym <= XK_Tslash)
                lower.* += (XK_rcedilla - XK_Rcedilla)
            else if (keysym >= XK_rcedilla and keysym <= XK_tslash)
                upper.* -= (XK_rcedilla - XK_Rcedilla)
            else if (keysym == XK_ENG)
                lower.* = XK_eng
            else if (keysym == XK_eng)
                upper.* = XK_ENG
            else if (keysym >= XK_Amacron and keysym <= XK_Umacron)
                lower.* += (XK_amacron - XK_Amacron)
            else if (keysym >= XK_amacron and keysym <= XK_umacron)
                upper.* -= (XK_amacron - XK_Amacron);
        },
        // Cyrillic
        6 => {
            if (keysym >= XK_Serbian_DJE and keysym <= XK_Serbian_DZE)
                lower.* -= (XK_Serbian_DJE - XK_Serbian_dje)
            else if (keysym >= XK_Serbian_dje and keysym <= XK_Serbian_dze)
                upper.* += (XK_Serbian_DJE - XK_Serbian_dje)
            else if (keysym >= XK_Cyrillic_YU and keysym <= XK_Cyrillic_HARDSIGN)
                lower.* -= (XK_Cyrillic_YU - XK_Cyrillic_yu)
            else if (keysym >= XK_Cyrillic_yu and keysym <= XK_Cyrillic_hardsign)
                upper.* += (XK_Cyrillic_YU - XK_Cyrillic_yu);
        },
        // Greek
        7 => {
            if (keysym >= XK_Greek_ALPHAaccent and keysym <= XK_Greek_OMEGAaccent)
                lower.* += (XK_Greek_alphaaccent - XK_Greek_ALPHAaccent)
            else if (keysym >= XK_Greek_alphaaccent and keysym <= XK_Greek_omegaaccent and
                keysym != XK_Greek_iotaaccentdieresis and
                keysym != XK_Greek_upsilonaccentdieresis)
                upper.* -= (XK_Greek_alphaaccent - XK_Greek_ALPHAaccent)
            else if (keysym >= XK_Greek_ALPHA and keysym <= XK_Greek_OMEGA)
                lower.* += (XK_Greek_alpha - XK_Greek_ALPHA)
            else if (keysym == XK_Greek_finalsmallsigma)
                upper.* = XK_Greek_SIGMA
            else if (keysym >= XK_Greek_alpha and keysym <= XK_Greek_omega)
                upper.* -= (XK_Greek_alpha - XK_Greek_ALPHA);
        },
        // Latin 9
        0x13 => {
            if (keysym == XK_OE)
                lower.* = XK_oe
            else if (keysym == XK_oe)
                upper.* = XK_OE
            else if (keysym == XK_Ydiaeresis)
                lower.* = XK_ydiaeresis;
        },
        else => {},
    }
}

/// Converts unicode cases
fn ucsConvertCase(code: Types.Keysym, lower: *Types.Keysym, upper: *Types.Keysym) void {
    const IPAExt_upper_mapping = [_]u16{
        0x0181, 0x0186, 0x0255, 0x0189, 0x018A,
        0x0258, 0x018F, 0x025A, 0x0190, 0x025C,
        0x025D, 0x025E, 0x025F, 0x0193, 0x0261,
        0x0262, 0x0194, 0x0264, 0x0265, 0x0266,
        0x0267, 0x0197, 0x0196, 0x026A, 0x026B,
        0x026C, 0x026D, 0x026E, 0x019C, 0x0270,
        0x0271, 0x019D, 0x0273, 0x0274, 0x019F,
        0x0276, 0x0277, 0x0278, 0x0279, 0x027A,
        0x027B, 0x027C, 0x027D, 0x027E, 0x0_27F,
        0x01A6, 0x0281, 0x0282, 0x01A9, 0x0284,
        0x0285, 0x0286, 0x0287, 0x01AE, 0x0289,
        0x01B1, 0x01B2, 0x028C, 0x028D, 0x028E,
        0x028F, 0x0290, 0x0291, 0x01B7,
    };

    const latinExtB_upper_mapping = [_]u16{
        0x0180, 0x0181, 0x0182, 0x0182, 0x0184, 0x0184, 0x0186, 0x0187,
        0x0187, 0x0189, 0x018A, 0x018B, 0x018B, 0x018D, 0x018E, 0x018F,
        0x0190, 0x0191, 0x0191, 0x0193, 0x0194, 0x01F6, 0x0196, 0x0197,
        0x0198, 0x0198, 0x019A, 0x019B, 0x019C, 0x019D, 0x0220, 0x019F,
        0x01A0, 0x01A0, 0x01A2, 0x01A2, 0x01A4, 0x01A4, 0x01A6, 0x01A7,
        0x01A7, 0x01A9, 0x01AA, 0x01AB, 0x01AC, 0x01AC, 0x01AE, 0x01AF,
        0x01AF, 0x01B1, 0x01B2, 0x01B3, 0x01B3, 0x01B5, 0x01B5, 0x01B7,
        0x01B8, 0x01B8, 0x01BA, 0x01BB, 0x01BC, 0x01BC, 0x01BE, 0x01F7,
        0x01C0, 0x01C1, 0x01C2, 0x01C3, 0x01C4, 0x01C4, 0x01C4, 0x01C7,
        0x01C7, 0x01C7, 0x01CA, 0x01CA, 0x01CA,
    };

    const latinExtB_lower_mapping = [_]u16{
        0x0180, 0x0253, 0x0183, 0x0183, 0x0185, 0x0185, 0x0254, 0x0188,
        0x0188, 0x0256, 0x0257, 0x018C, 0x018C, 0x018D, 0x01DD, 0x0259,
        0x025B, 0x0192, 0x0192, 0x0260, 0x0263, 0x0195, 0x0269, 0x0268,
        0x0199, 0x0199, 0x019A, 0x019B, 0x026F, 0x0272, 0x019E, 0x0275,
        0x01A1, 0x01A1, 0x01A3, 0x01A3, 0x01A5, 0x01A5, 0x0280, 0x01A8,
        0x01A8, 0x0283, 0x01AA, 0x01AB, 0x01AD, 0x01AD, 0x0288, 0x01B0,
        0x01B0, 0x028A, 0x028B, 0x01B4, 0x01B4, 0x01B6, 0x01B6, 0x0292,
        0x01B9, 0x01B9, 0x01BA, 0x01BB, 0x01BD, 0x01BD, 0x01BE, 0x01BF,
        0x01C0, 0x01C1, 0x01C2, 0x01C3, 0x01C6, 0x01C6, 0x01C6, 0x01C9,
        0x01C9, 0x01C9, 0x01CC, 0x01CC, 0x01CC,
    };

    const greek_upper_mapping = [_]u16{
        0x0000, 0x0000, 0x0000, 0x0000, 0x0374, 0x0375, 0x0000, 0x0000,
        0x0000, 0x0000, 0x037A, 0x0000, 0x0000, 0x0000, 0x037E, 0x0000,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0384, 0x0385, 0x0386, 0x0387,
        0x0388, 0x0389, 0x038A, 0x0000, 0x038C, 0x0000, 0x038E, 0x038F,
        0x0390, 0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397,
        0x0398, 0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F,
        0x03A0, 0x03A1, 0x0000, 0x03A3, 0x03A4, 0x03A5, 0x03A6, 0x03A7,
        0x03A8, 0x03A9, 0x03AA, 0x03AB, 0x0386, 0x0388, 0x0389, 0x038A,
        0x03B0, 0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397,
        0x0398, 0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F,
        0x03A0, 0x03A1, 0x03A3, 0x03A3, 0x03A4, 0x03A5, 0x03A6, 0x03A7,
        0x03A8, 0x03A9, 0x03AA, 0x03AB, 0x038C, 0x038E, 0x038F, 0x0000,
        0x0392, 0x0398, 0x03D2, 0x03D3, 0x03D4, 0x03A6, 0x03A0, 0x03D7,
        0x03D8, 0x03D8, 0x03DA, 0x03DA, 0x03DC, 0x03DC, 0x03DE, 0x03DE,
        0x03E0, 0x03E0, 0x03E2, 0x03E2, 0x03E4, 0x03E4, 0x03E6, 0x03E6,
        0x03E8, 0x03E8, 0x03EA, 0x03EA, 0x03EC, 0x03EC, 0x03EE, 0x03EE,
        0x039A, 0x03A1, 0x03F9, 0x03F3, 0x03F4, 0x0395, 0x03F6, 0x03F7,
        0x03F7, 0x03F9, 0x03FA, 0x03FA, 0x0000, 0x0000, 0x0000, 0x0000,
    };

    const greek_lower_mapping = [_]u16{
        0x0000, 0x0000, 0x0000, 0x0000, 0x0374, 0x0375, 0x0000, 0x0000,
        0x0000, 0x0000, 0x037A, 0x0000, 0x0000, 0x0000, 0x037E, 0x0000,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0384, 0x0385, 0x03AC, 0x0387,
        0x03AD, 0x03AE, 0x03AF, 0x0000, 0x03CC, 0x0000, 0x03CD, 0x03CE,
        0x0390, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7,
        0x03B8, 0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF,
        0x03C0, 0x03C1, 0x0000, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7,
        0x03C8, 0x03C9, 0x03CA, 0x03CB, 0x03AC, 0x03AD, 0x03AE, 0x03AF,
        0x03B0, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7,
        0x03B8, 0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF,
        0x03C0, 0x03C1, 0x03C2, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7,
        0x03C8, 0x03C9, 0x03CA, 0x03CB, 0x03CC, 0x03CD, 0x03CE, 0x0000,
        0x03D0, 0x03D1, 0x03D2, 0x03D3, 0x03D4, 0x03D5, 0x03D6, 0x03D7,
        0x03D9, 0x03D9, 0x03DB, 0x03DB, 0x03DD, 0x03DD, 0x03DF, 0x03DF,
        0x03E1, 0x03E1, 0x03E3, 0x03E3, 0x03E5, 0x03E5, 0x03E7, 0x03E7,
        0x03E9, 0x03E9, 0x03EB, 0x03EB, 0x03ED, 0x03ED, 0x03EF, 0x03EF,
        0x03F0, 0x03F1, 0x03F2, 0x03F3, 0x03B8, 0x03F5, 0x03F6, 0x03F8,
        0x03F8, 0x03F2, 0x03FB, 0x03FB, 0x0000, 0x0000, 0x0000, 0x0000,
    };

    const greekExt_lower_mapping = [_]u16{
        0x1F00, 0x1F01, 0x1F02, 0x1F03, 0x1F04, 0x1F05, 0x1F06, 0x1F07,
        0x1F00, 0x1F01, 0x1F02, 0x1F03, 0x1F04, 0x1F05, 0x1F06, 0x1F07,
        0x1F10, 0x1F11, 0x1F12, 0x1F13, 0x1F14, 0x1F15, 0x0000, 0x0000,
        0x1F10, 0x1F11, 0x1F12, 0x1F13, 0x1F14, 0x1F15, 0x0000, 0x0000,
        0x1F20, 0x1F21, 0x1F22, 0x1F23, 0x1F24, 0x1F25, 0x1F26, 0x1F27,
        0x1F20, 0x1F21, 0x1F22, 0x1F23, 0x1F24, 0x1F25, 0x1F26, 0x1F27,
        0x1F30, 0x1F31, 0x1F32, 0x1F33, 0x1F34, 0x1F35, 0x1F36, 0x1F37,
        0x1F30, 0x1F31, 0x1F32, 0x1F33, 0x1F34, 0x1F35, 0x1F36, 0x1F37,
        0x1F40, 0x1F41, 0x1F42, 0x1F43, 0x1F44, 0x1F45, 0x0000, 0x0000,
        0x1F40, 0x1F41, 0x1F42, 0x1F43, 0x1F44, 0x1F45, 0x0000, 0x0000,
        0x1F50, 0x1F51, 0x1F52, 0x1F53, 0x1F54, 0x1F55, 0x1F56, 0x1F57,
        0x0000, 0x1F51, 0x0000, 0x1F53, 0x0000, 0x1F55, 0x0000, 0x1F57,
        0x1F60, 0x1F61, 0x1F62, 0x1F63, 0x1F64, 0x1F65, 0x1F66, 0x1F67,
        0x1F60, 0x1F61, 0x1F62, 0x1F63, 0x1F64, 0x1F65, 0x1F66, 0x1F67,
        0x1F70, 0x1F71, 0x1F72, 0x1F73, 0x1F74, 0x1F75, 0x1F76, 0x1F77,
        0x1F78, 0x1F79, 0x1F7A, 0x1F7B, 0x1F7C, 0x1F7D, 0x0000, 0x0000,
        0x1F80, 0x1F81, 0x1F82, 0x1F83, 0x1F84, 0x1F85, 0x1F86, 0x1F87,
        0x1F80, 0x1F81, 0x1F82, 0x1F83, 0x1F84, 0x1F85, 0x1F86, 0x1F87,
        0x1F90, 0x1F91, 0x1F92, 0x1F93, 0x1F94, 0x1F95, 0x1F96, 0x1F97,
        0x1F90, 0x1F91, 0x1F92, 0x1F93, 0x1F94, 0x1F95, 0x1F96, 0x1F97,
        0x1FA0, 0x1FA1, 0x1FA2, 0x1FA3, 0x1FA4, 0x1FA5, 0x1FA6, 0x1FA7,
        0x1FA0, 0x1FA1, 0x1FA2, 0x1FA3, 0x1FA4, 0x1FA5, 0x1FA6, 0x1FA7,
        0x1FB0, 0x1FB1, 0x1FB2, 0x1FB3, 0x1FB4, 0x0000, 0x1FB6, 0x1FB7,
        0x1FB0, 0x1FB1, 0x1F70, 0x1F71, 0x1FB3, 0x1FBD, 0x1FBE, 0x1FBF,
        0x1FC0, 0x1FC1, 0x1FC2, 0x1FC3, 0x1FC4, 0x0000, 0x1FC6, 0x1FC7,
        0x1F72, 0x1F73, 0x1F74, 0x1F75, 0x1FC3, 0x1FCD, 0x1FCE, 0x1FCF,
        0x1FD0, 0x1FD1, 0x1FD2, 0x1FD3, 0x0000, 0x0000, 0x1FD6, 0x1FD7,
        0x1FD0, 0x1FD1, 0x1F76, 0x1F77, 0x0000, 0x1FDD, 0x1FDE, 0x1FDF,
        0x1FE0, 0x1FE1, 0x1FE2, 0x1FE3, 0x1FE4, 0x1FE5, 0x1FE6, 0x1FE7,
        0x1FE0, 0x1FE1, 0x1F7A, 0x1F7B, 0x1FE5, 0x1FED, 0x1FEE, 0x1FEF,
        0x0000, 0x0000, 0x1FF2, 0x1FF3, 0x1FF4, 0x0000, 0x1FF6, 0x1FF7,
        0x1F78, 0x1F79, 0x1F7C, 0x1F7D, 0x1FF3, 0x1FFD, 0x1FFE, 0x0000,
    };

    const greekExt_upper_mapping = [_]u32{
        0x1F08, 0x1F09, 0x1F0A, 0x1F0B, 0x1F0C, 0x1F0D, 0x1F0E, 0x1F0F,
        0x1F08, 0x1F09, 0x1F0A, 0x1F0B, 0x1F0C, 0x1F0D, 0x1F0E, 0x1F0F,
        0x1F18, 0x1F19, 0x1F1A, 0x1F1B, 0x1F1C, 0x1F1D, 0x0000, 0x0000,
        0x1F18, 0x1F19, 0x1F1A, 0x1F1B, 0x1F1C, 0x1F1D, 0x0000, 0x0000,
        0x1F28, 0x1F29, 0x1F2A, 0x1F2B, 0x1F2C, 0x1F2D, 0x1F2E, 0x1F2F,
        0x1F28, 0x1F29, 0x1F2A, 0x1F2B, 0x1F2C, 0x1F2D, 0x1F2E, 0x1F2F,
        0x1F38, 0x1F39, 0x1F3A, 0x1F3B, 0x1F3C, 0x1F3D, 0x1F3E, 0x1F3F,
        0x1F38, 0x1F39, 0x1F3A, 0x1F3B, 0x1F3C, 0x1F3D, 0x1F3E, 0x1F3F,
        0x1F48, 0x1F49, 0x1F4A, 0x1F4B, 0x1F4C, 0x1F4D, 0x0000, 0x0000,
        0x1F48, 0x1F49, 0x1F4A, 0x1F4B, 0x1F4C, 0x1F4D, 0x0000, 0x0000,
        0x1F50, 0x1F59, 0x1F52, 0x1F5B, 0x1F54, 0x1F5D, 0x1F56, 0x1F5F,
        0x0000, 0x1F59, 0x0000, 0x1F5B, 0x0000, 0x1F5D, 0x0000, 0x1F5F,
        0x1F68, 0x1F69, 0x1F6A, 0x1F6B, 0x1F6C, 0x1F6D, 0x1F6E, 0x1F6F,
        0x1F68, 0x1F69, 0x1F6A, 0x1F6B, 0x1F6C, 0x1F6D, 0x1F6E, 0x1F6F,
        0x1FBA, 0x1FBB, 0x1FC8, 0x1FC9, 0x1FCA, 0x1FCB, 0x1FDA, 0x1FDB,
        0x1FF8, 0x1FF9, 0x1FEA, 0x1FEB, 0x1FFA, 0x1FFB, 0x0000, 0x0000,
        0x1F88, 0x1F89, 0x1F8A, 0x1F8B, 0x1F8C, 0x1F8D, 0x1F8E, 0x1F8F,
        0x1F88, 0x1F89, 0x1F8A, 0x1F8B, 0x1F8C, 0x1F8D, 0x1F8E, 0x1F8F,
        0x1F98, 0x1F99, 0x1F9A, 0x1F9B, 0x1F9C, 0x1F9D, 0x1F9E, 0x1F9F,
        0x1F98, 0x1F99, 0x1F9A, 0x1F9B, 0x1F9C, 0x1F9D, 0x1F9E, 0x1F9F,
        0x1FA8, 0x1FA9, 0x1FAA, 0x1FAB, 0x1FAC, 0x1FAD, 0x1FAE, 0x1FAF,
        0x1FA8, 0x1FA9, 0x1FAA, 0x1FAB, 0x1FAC, 0x1FAD, 0x1FAE, 0x1FAF,
        0x1FB8, 0x1FB9, 0x1FB2, 0x1FBC, 0x1FB4, 0x0000, 0x1FB6, 0x1FB7,
        0x1FB8, 0x1FB9, 0x1FBA, 0x1FBB, 0x1FBC, 0x1FBD, 0x0399, 0x1FBF,
        0x1FC0, 0x1FC1, 0x1FC2, 0x1FCC, 0x1FC4, 0x0000, 0x1FC6, 0x1FC7,
        0x1FC8, 0x1FC9, 0x1FCA, 0x1FCB, 0x1FCC, 0x1FCD, 0x1FCE, 0x1FCF,
        0x1FD8, 0x1FD9, 0x1FD2, 0x1FD3, 0x0000, 0x0000, 0x1FD6, 0x1FD7,
        0x1FD8, 0x1FD9, 0x1FDA, 0x1FDB, 0x0000, 0x1FDD, 0x1FDE, 0x1FDF,
        0x1FE8, 0x1FE9, 0x1FE2, 0x1FE3, 0x1FE4, 0x1FEC, 0x1FE6, 0x1FE7,
        0x1FE8, 0x1FE9, 0x1FEA, 0x1FEB, 0x1FEC, 0x1FED, 0x1FEE, 0x1FEF,
        0x0000, 0x0000, 0x1FF2, 0x1FFC, 0x1FF4, 0x0000, 0x1FF6, 0x1FF7,
        0x1FF8, 0x1FF9, 0x1FFA, 0x1FFB, 0x1FFC, 0x1FFD, 0x1FFE, 0x0000,
    };

    lower.* = code;
    upper.* = code;

    // Basic Latin and Latin-1 Supplement, U+0000 to U+00FF
    if (code <= 0x00ff) {
        if (code >= 0x0041 and code <= 0x005a)
            lower.* += 0x20
        else if (code >= 0x0061 and code <= 0x007a)
            upper.* -= 0x20
        else if ((code >= 0x00c0 and code <= 0x00d6) or
            (code >= 0x00d8 and code <= 0x00de))
            lower.* += 0x20
        else if ((code >= 0x00e0 and code <= 0x00f6) or
            (code >= 0x00f8 and code <= 0x00fe))
            upper.* -= 0x20
        else if (code == 0x00ff)
            upper.* = 0x0178
        else if (code == 0x00b5)
            upper.* = 0x039c
        else if (code == 0x00df)
            upper.* = 0x1e9e;
        return;
    }

    // Latin Extended-A, U+0100 to U+017F
    if (code >= 0x0100 and code <= 0x017f) {
        if ((code >= 0x0100 and code <= 0x012f) or
            (code >= 0x0132 and code <= 0x0137) or
            (code >= 0x014a and code <= 0x0177))
        {
            upper.* = code & ~@as(u32, 1);
            lower.* = code | 1;
        } else if ((code >= 0x0139 and code <= 0x0148) or
            (code >= 0x0179 and code <= 0x017e))
        {
            if (code & 1 == 1)
                lower.* += 1
            else
                upper.* -= 1;
        } else if (code == 0x0130)
            lower.* = 0x0069
        else if (code == 0x0131)
            upper.* = 0x0049
        else if (code == 0x0178)
            lower.* = 0x00ff
        else if (code == 0x017f)
            upper.* = 0x0053;
        return;
    }

    // Latin Extended-B, U+0180 to U+024F
    if (code >= 0x0180 and code <= 0x024f) {
        if (code >= 0x01cd and code <= 0x01dc) {
            if (code & 1 == 1)
                lower.* += 1
            else
                upper.* -= 1;
        } else if ((code >= 0x01de and code <= 0x01ef) or
            (code >= 0x01f4 and code <= 0x01f5) or
            (code >= 0x01f8 and code <= 0x021f) or
            (code >= 0x0222 and code <= 0x0233))
        {
            lower.* |= 1;
            upper.* &= ~@as(u32, 1);
        } else if (code >= 0x0180 and code <= 0x01cc) {
            lower.* = latinExtB_lower_mapping[code - 0x0180];
            upper.* = latinExtB_upper_mapping[code - 0x0180];
        } else if (code == 0x01dd)
            upper.* = 0x018e
        else if (code == 0x01f1 or code == 0x01f2) {
            lower.* = 0x01f3;
            upper.* = 0x01f1;
        } else if (code == 0x01f3)
            upper.* = 0x01f1
        else if (code == 0x01f6)
            lower.* = 0x0195
        else if (code == 0x01f7)
            lower.* = 0x01bf
        else if (code == 0x0220)
            lower.* = 0x019e;
        return;
    }

    // IPA Extensions, U+0250 to U+02AF
    if (code >= 0x0253 and code <= 0x0292) {
        upper.* = IPAExt_upper_mapping[code - 0x0253];
    }

    // Combining Diacritical Marks, U+0300 to U+036F
    if (code == 0x0345) {
        upper.* = 0x0399;
    }

    // Greek and Coptic, U+0370 to U+03FF
    if (code >= 0x0370 and code <= 0x03ff) {
        lower.* = greek_lower_mapping[code - 0x0370];
        upper.* = greek_upper_mapping[code - 0x0370];
        if (upper.* == 0)
            upper.* = code;
        if (lower.* == 0)
            lower.* = code;
    }

    // Cyrillic and Cyrillic Supplementary, U+0400 to U+052F
    if ((code >= 0x0400 and code <= 0x04ff) or
        (code >= 0x0500 and code <= 0x052f))
    {
        if (code >= 0x0400 and code <= 0x040f)
            lower.* += 0x50
        else if (code >= 0x0410 and code <= 0x042f)
            lower.* += 0x20
        else if (code >= 0x0430 and code <= 0x044f)
            upper.* -= 0x20
        else if (code >= 0x0450 and code <= 0x045f)
            upper.* -= 0x50
        else if ((code >= 0x0460 and code <= 0x0481) or
            (code >= 0x048a and code <= 0x04bf) or
            (code >= 0x04d0 and code <= 0x04f5) or
            (code >= 0x04f8 and code <= 0x04f9) or
            (code >= 0x0500 and code <= 0x050f))
        {
            upper.* &= ~@as(u32, 1);
            lower.* |= 1;
        } else if (code >= 0x04c1 and code <= 0x04ce) {
            if (code & 1 == 1)
                lower.* += 1
            else
                upper.* -= 1;
        }
    }

    // Armenian, U+0530 to U+058F
    if (code >= 0x0530 and code <= 0x058f) {
        if (code >= 0x0531 and code <= 0x0556)
            lower.* += 0x30
        else if (code >= 0x0561 and code <= 0x0586)
            upper.* -= 0x30;
    }

    // Latin Extended Additional, U+1E00 to U+1EFF
    if (code >= 0x1e00 and code <= 0x1eff) {
        if ((code >= 0x1e00 and code <= 0x1e95) or
            (code >= 0x1ea0 and code <= 0x1ef9))
        {
            upper.* &= ~@as(u32, 1);
            lower.* |= 1;
        } else if (code == 0x1e9b)
            upper.* = 0x1e60
        else if (code == 0x1e9e)
            lower.* = 0x00df;
    }

    // Greek Extended, U+1F00 to U+1FFF
    if (code >= 0x1f00 and code <= 0x1fff) {
        lower.* = greekExt_lower_mapping[code - 0x1f00];
        upper.* = greekExt_upper_mapping[code - 0x1f00];
        if (upper.* == 0)
            upper.* = code;
        if (lower.* == 0)
            lower.* = code;
    }

    // Letterlike Symbols, U+2100 to U+214F
    if (code >= 0x2100 and code <= 0x214f) {
        lower.* = switch (code) {
            0x2126 => 0x03c9,
            0x212a => 0x006b,
            0x212b => 0x00e5,
            else => unreachable,
        };
    }

    // Number Forms, U+2150 to U+218F
    else if (code >= 0x2160 and code <= 0x216f)
        lower.* += 0x10
    else if (code >= 0x2170 and code <= 0x217f)
        upper.* -= 0x10
    else if (code >= 0x24b6 and code <= 0x24cf)
        lower.* += 0x1a
    else if (code >= 0x24d0 and code <= 0x24e9)
        upper.* -= 0x1a
    else if (code >= 0xff21 and code <= 0xff3a)
        lower.* += 0x20
    else if (code >= 0xff41 and code <= 0xff5a)
        upper.* -= 0x20
    else if (code >= 0x10400 and code <= 0x10427)
        lower.* += 0x28
    else if (code >= 0x10428 and code <= 0x1044f)
        upper.* -= 0x28;
}
