"""256×256 RGBA display framebuffer with PIL-based drawing.

Behavior mirrors Halo firmware 0.8.8 (modules/halo/src/lua_display.c and
modules/canvas/canvas.c): RGB global palette, non-wrapping palette_offset,
Dogica GFX fonts, 1-based coordinates low-clamped to 1.
"""
from __future__ import annotations

import threading
from typing import Sequence

import numpy as np
from PIL import Image, ImageDraw

from halo_emulator.gfx_fonts import FONT_LIST, GfxFont

# Named palette entries (0-based, matching the firmware's assign_color index)
PALETTE_NAMES: dict[str, int] = {
    "VOID": 0,
    "WHITE": 1,
    "GREY": 2,
    "RED": 3,
    "PINK": 4,
    "DARKBROWN": 5,
    "BROWN": 6,
    "ORANGE": 7,
    "YELLOW": 8,
    "DARKGREEN": 9,
    "GREEN": 10,
    "LIGHTGREEN": 11,
    "NIGHTBLUE": 12,
    "SEABLUE": 13,
    "SKYBLUE": 14,
    "CLOUDBLUE": 15,
}

# Firmware default palette (lua_display.c, stored as RGB since 0.8.8)
_DEFAULT_PALETTE: list[tuple[int, int, int]] = [
    (0, 0, 0),        # 0 VOID
    (255, 255, 255),  # 1 WHITE
    (128, 128, 128),  # 2 GREY
    (255, 0, 0),      # 3 RED
    (255, 192, 203),  # 4 PINK
    (101, 67, 33),    # 5 DARKBROWN
    (150, 75, 0),     # 6 BROWN
    (255, 165, 0),    # 7 ORANGE
    (255, 255, 0),    # 8 YELLOW
    (0, 100, 0),      # 9 DARKGREEN
    (0, 255, 0),      # 10 GREEN
    (144, 238, 144),  # 11 LIGHTGREEN
    (25, 25, 112),    # 12 NIGHTBLUE
    (0, 0, 205),      # 13 SEABLUE
    (135, 206, 235),  # 14 SKYBLUE
    (240, 248, 255),  # 15 CLOUDBLUE
]

WIDTH = 256
HEIGHT = 256

# set_brightness level (-2..2) <-> percent, as in the firmware
_BRIGHTNESS_LEVEL_TO_PERCENT = {-2: 10, -1: 25, 0: 50, 1: 75, 2: 100}
_BRIGHTNESS_PERCENT_TO_LEVEL = {10: -2, 25: -1, 50: 0, 75: 1, 100: 2}


def _rgb_from_int(color: int) -> tuple[int, int, int]:
    """Convert 0xRRGGBB integer to (r, g, b) tuple."""
    r = (color >> 16) & 0xFF
    g = (color >> 8) & 0xFF
    b = color & 0xFF
    return (r, g, b)


def _clamp_u8(value: int) -> int:
    return 0 if value < 0 else 255 if value > 255 else value


def _ycbcr_to_rgb(y: int, cb: int, cr: int) -> tuple[int, int, int]:
    """Convert 4-bit Y, 3-bit Cb/Cr to RGB888 (firmware ycbcr_to_rgb888_fast)."""
    y_scaled = (y * 219 // 15) + 16
    cb_scaled = (cb * 224 // 7) + 16
    cr_scaled = (cr * 224 // 7) + 16
    cb_offset = cb_scaled - 128
    cr_offset = cr_scaled - 128
    r = y_scaled + ((91881 * cr_offset) >> 16)
    g = y_scaled - ((22554 * cb_offset + 46788 * cr_offset) >> 16)
    b = y_scaled + ((116130 * cb_offset) >> 16)
    return (_clamp_u8(r), _clamp_u8(g), _clamp_u8(b))


def _unpack_1bit(data: bytes) -> list[int]:
    arr = np.frombuffer(data, dtype=np.uint8)
    return list(np.unpackbits(arr))


def _unpack_2bit(data: bytes) -> list[int]:
    result = []
    for byte in data:
        result.append((byte >> 6) & 0x3)
        result.append((byte >> 4) & 0x3)
        result.append((byte >> 2) & 0x3)
        result.append(byte & 0x3)
    return result


def _unpack_4bit(data: bytes) -> list[int]:
    result = []
    for byte in data:
        result.append((byte >> 4) & 0xF)
        result.append(byte & 0xF)
    return result


def _low_clamp(v: int) -> int:
    """Firmware clamps 1-based coordinates low to 1 (no high clamp)."""
    v = int(v)
    return 1 if v < 1 else v


class DisplayBuffer:
    """256×256 RGBA display with a 16-entry palette and PIL-based drawing.

    Halo draws directly to display memory — there is no double-buffering.
    Every draw call is immediately visible; ``show()`` is a no-op.
    """

    def __init__(self) -> None:
        self._palette: list[tuple[int, int, int]] = list(_DEFAULT_PALETTE)
        self._display: Image.Image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 255))
        self._draw: ImageDraw.ImageDraw = ImageDraw.Draw(self._display)
        self._lock = threading.RLock()
        self._brightness_percent: int = 50
        self._pan_x: int = 0
        self._pan_y: int = 0
        self._suspended: bool = False  # power_save state
        self._font_id: int = 0  # Dogica
        self._font_mult: int = 1  # (size/8) * scale
        self._runtime = None  # lupa runtime, set by build_lua_runtime

    # ------------------------------------------------------------------ palette

    def _resolve_index(self, index: int | str) -> int:
        """Resolve a palette index (0-based int or named string), as firmware does."""
        if isinstance(index, str):
            name = index.upper()
            if name not in PALETTE_NAMES:
                raise ValueError(f"invalid color name: {index}")
            return PALETTE_NAMES[name]
        i = int(index)
        if i < 0 or i > 15:
            raise ValueError("color_index must be between 0 and 15")
        return i

    def assign_color(self, index: int | str, r: int, g: int, b: int) -> None:
        i = self._resolve_index(index)
        r, g, b = int(r), int(g), int(b)
        if not all(0 <= v <= 255 for v in (r, g, b)):
            raise ValueError("RGB values must be between 0 and 255")
        self._palette[i] = (r, g, b)

    def assign_color_ycbcr(self, index: int | str, y: int, cb: int, cr: int) -> None:
        i = self._resolve_index(index)
        y, cb, cr = int(y), int(cb), int(cr)
        if not 0 <= y <= 15:
            raise ValueError("Y value must be between 0 and 15 (4-bit)")
        if not 0 <= cb <= 7:
            raise ValueError("Cb value must be between 0 and 7 (3-bit)")
        if not 0 <= cr <= 7:
            raise ValueError("Cr value must be between 0 and 7 (3-bit)")
        self._palette[i] = _ycbcr_to_rgb(y, cb, cr)

    # ------------------------------------------------------------------ clear/show

    def clear(self, color: int = 0) -> None:
        """Clear display to a 0xRRGGBB color (default black)."""
        rgb = _rgb_from_int(int(color))
        with self._lock:
            self._display.paste(rgb + (255,), [0, 0, WIDTH, HEIGHT])
            self._draw = ImageDraw.Draw(self._display)

    def show(self, enable: bool = True) -> None:
        """No-op. Halo draws directly to display memory; there is no buffer flip."""

    def get_image(self) -> Image.Image:
        """Return a copy of the current display contents as a PIL Image."""
        with self._lock:
            return self._display.copy()

    # ------------------------------------------------------------------ primitives

    def set_pixel(self, x: int, y: int, color: int) -> None:
        rgb = _rgb_from_int(int(color))
        px, py = _low_clamp(x) - 1, _low_clamp(y) - 1
        if px < WIDTH and py < HEIGHT:
            self._display.putpixel((px, py), rgb + (255,))

    def line(self, x0: int, y0: int, x1: int, y1: int, color: int) -> None:
        rgb = _rgb_from_int(int(color))
        self._draw.line(
            [(_low_clamp(x0) - 1, _low_clamp(y0) - 1), (_low_clamp(x1) - 1, _low_clamp(y1) - 1)],
            fill=rgb + (255,),
        )

    def rect(self, x: int, y: int, w: int, h: int, color: int, filled: bool = False) -> None:
        rgb = _rgb_from_int(int(color))
        w, h = int(w), int(h)
        if w <= 0 or h <= 0:
            return
        x0, y0 = _low_clamp(x) - 1, _low_clamp(y) - 1
        x1, y1 = x0 + w - 1, y0 + h - 1
        if filled:
            self._draw.rectangle([x0, y0, x1, y1], fill=rgb + (255,))
        else:
            self._draw.rectangle([x0, y0, x1, y1], outline=rgb + (255,))

    def circle(self, cx: int, cy: int, r: int, color: int, filled: bool = False) -> None:
        rgb = _rgb_from_int(int(color))
        cx0, cy0 = _low_clamp(cx) - 1, _low_clamp(cy) - 1
        r = int(r)
        bbox = [cx0 - r, cy0 - r, cx0 + r, cy0 + r]
        if filled:
            self._draw.ellipse(bbox, fill=rgb + (255,))
        else:
            self._draw.ellipse(bbox, outline=rgb + (255,))

    def polygon(self, points: object, color: int) -> None:
        """Draw a filled polygon.

        `points` is a flat Lua table of alternating x, y coordinates:
        ``{x1, y1, x2, y2, x3, y3, ...}`` (1-based).
        """
        rgb = _rgb_from_int(int(color))
        try:
            flat = [int(v) for v in points.values()]  # type: ignore[union-attr]
        except AttributeError:
            flat = [int(v) for v in points]  # type: ignore[arg-type]
        if len(flat) > 64:
            raise ValueError("too many polygon points (max 64)")
        # Pair up into 0-based (x, y) tuples
        coords = [
            (_low_clamp(flat[i]) - 1, _low_clamp(flat[i + 1]) - 1)
            for i in range(0, len(flat) - 1, 2)
        ]
        if len(coords) >= 2:
            self._draw.polygon(coords, fill=rgb + (255,))

    # ------------------------------------------------------------------ text / font

    def set_font(self, font_id: int, size: int = 8, scale: int = 1) -> None:
        font_id, size, scale = int(font_id), int(size), int(scale)
        if font_id not in FONT_LIST:
            raise ValueError("invalid font id (must be 0-1)")
        if size < 8 or size % 8 != 0:
            raise ValueError("invalid font size (must be a multiple of 8)")
        if scale < 1 or (size // 8) * scale > 255:
            raise ValueError("invalid scale")
        self._font_id = font_id
        self._font_mult = (size // 8) * scale

    def get_font_list(self) -> object:
        """Return the firmware-shaped font table: {[0]="Dogica", [1]="DogicaBold"}."""
        if self._runtime is not None:
            t = self._runtime.table()
            for font_id, (name, _font) in FONT_LIST.items():
                t[font_id] = name
            return t
        return {font_id: name for font_id, (name, _font) in FONT_LIST.items()}

    def _draw_gfx_char(
        self, font: GfxFont, mult: int, c: int, x: int, y: int,
        rgb: tuple[int, int, int],
    ) -> int:
        """Port of canvas_draw_char: returns the x-advance in pixels.

        `x`, `y` are 0-based; `y` is the top of the cap-height box (the
        firmware measures ascent from 'H' and shifts to the baseline).
        Mirrors the firmware's inclusive-endpoint horizontal-run quirk at
        mult == 1, which paints one extra trailing pixel per run.
        """
        if c < font.first or c > font.last:
            return 0
        glyph = font.glyphs[c - font.first]
        ascent = font.glyphs[ord("H") - font.first].y_offset  # -7 for Dogica
        y -= ascent * mult  # baseline
        fill = rgb + (255,)

        def hline(x0: int, x1: int, yy: int) -> None:
            # canvas_draw_line: inclusive endpoints, clipped to the panel
            if yy < 0 or yy >= HEIGHT:
                return
            x0, x1 = max(0, x0), min(WIDTH - 1, x1)
            for px in range(x0, x1 + 1):
                self._display.putpixel((px, yy), fill)

        def rect_fill(x0: int, y0: int, w: int, h: int) -> None:
            if w <= 0 or h <= 0:
                return
            x1, y1 = x0 + w - 1, y0 + h - 1
            x0, y0 = max(0, x0), max(0, y0)
            x1, y1 = min(WIDTH - 1, x1), min(HEIGHT - 1, y1)
            if x0 <= x1 and y0 <= y1:
                self._draw.rectangle([x0, y0, x1, y1], fill=fill)

        bo = glyph.bitmap_offset
        bits = 0
        bit = 0
        xo, yo = glyph.x_offset, glyph.y_offset
        for yy in range(glyph.height):
            hpc = 0
            for xx in range(glyph.width):
                if bit == 0:
                    bits = font.bitmaps[bo]
                    bo += 1
                    bit = 0x80
                if bits & bit:
                    hpc += 1
                else:
                    if hpc:
                        if mult == 1:
                            hline(x + xo + xx - hpc, x + xo + xx, y + yo + yy)
                        else:
                            rect_fill(x + (xo + xx - hpc) * mult, y + (yo + yy) * mult,
                                      mult * hpc, mult)
                        hpc = 0
                bit >>= 1
            if hpc:
                xx = glyph.width
                if mult == 1:
                    hline(x + xo + xx - hpc, x + xo + xx, y + yo + yy)
                else:
                    rect_fill(x + (xo + xx - hpc) * mult, y + (yo + yy) * mult,
                              mult * hpc, mult)
        return glyph.x_advance * mult

    def text(self, txt: str, x: int, y: int, color: int = 0xFFFFFF) -> None:
        rgb = _rgb_from_int(int(color))
        font = FONT_LIST[self._font_id][1]
        px, py = _low_clamp(x) - 1, _low_clamp(y) - 1
        for ch in str(txt):
            px += self._draw_gfx_char(font, self._font_mult, ord(ch), px, py, rgb)

    def char(self, codepoint: int, x: int, y: int, color: int) -> None:
        rgb = _rgb_from_int(int(color))
        font = FONT_LIST[self._font_id][1]
        self._draw_gfx_char(
            font, self._font_mult, int(codepoint),
            _low_clamp(x) - 1, _low_clamp(y) - 1, rgb,
        )

    # ------------------------------------------------------------------ bitmap

    def bitmap(
        self,
        x: int, y: int,
        width: int,
        color_format: int,
        palette_offset: int,
        data: object,
        opts: object = None,
    ) -> None:
        """Draw an indexed-color or RGB888 bitmap."""
        # Decode data from lupa/Lua string to bytes
        if isinstance(data, (bytes, bytearray)):
            raw = bytes(data)
        else:
            raw = str(data).encode("latin-1")

        x_scale = 1
        y_scale = 1
        custom_palette_data: bytes | None = None

        if opts is not None:
            try:
                xs = opts.x_scale  # type: ignore[union-attr]
                if xs is not None:
                    x_scale = int(xs)
            except AttributeError:
                pass
            try:
                ys = opts.y_scale  # type: ignore[union-attr]
                if ys is not None:
                    y_scale = int(ys)
            except AttributeError:
                pass
            try:
                pd = opts.palette_data  # type: ignore[union-attr]
                if pd is not None:
                    if isinstance(pd, (bytes, bytearray)):
                        custom_palette_data = bytes(pd)
                    else:
                        custom_palette_data = str(pd).encode("latin-1")
            except AttributeError:
                pass

        if x_scale < 1 or y_scale < 1:
            raise ValueError("scale factors must be positive integers")

        fmt = int(color_format)
        if fmt not in (0, 2, 4, 16):
            raise ValueError(f"unsupported color format: {fmt}. Must be 0, 2, 4, or 16")

        offset = int(palette_offset)
        if offset < 0 or offset > 15:
            raise ValueError("palette_offset must be between 0 and 15")

        bx = _low_clamp(x) - 1
        by = _low_clamp(y) - 1
        w = int(width)

        if fmt == 0:
            # RGB888: 3 bytes per pixel, no palette
            num_pixels = len(raw) // 3
            h = num_pixels // w
            for row in range(h):
                for col in range(w):
                    idx = (row * w + col) * 3
                    r, g, b = raw[idx], raw[idx + 1], raw[idx + 2]
                    for dy in range(y_scale):
                        for dx in range(x_scale):
                            px = bx + col * x_scale + dx
                            py = by + row * y_scale + dy
                            if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                                self._display.putpixel((px, py), (r, g, b, 255))
            return

        # Palette-indexed: unpack pixels
        if fmt == 2:
            pixel_indices = _unpack_1bit(raw)
        elif fmt == 4:
            pixel_indices = _unpack_2bit(raw)
        else:
            pixel_indices = _unpack_4bit(raw)

        h = len(pixel_indices) // w
        if h <= 0:
            raise ValueError("invalid data length for given width and color format")

        # Build the 16-entry palette for this bitmap. A custom palette is
        # only honoured when it holds whole RGB triplets (as in firmware);
        # otherwise the global palette applies. Missing entries are
        # zero-filled.
        if (
            custom_palette_data is not None
            and len(custom_palette_data) >= 3
            and len(custom_palette_data) % 3 == 0
        ):
            local_pal = [
                (
                    custom_palette_data[i * 3],
                    custom_palette_data[i * 3 + 1],
                    custom_palette_data[i * 3 + 2],
                )
                for i in range(min(len(custom_palette_data) // 3, 16))
            ]
            local_pal += [(0, 0, 0)] * (16 - len(local_pal))
        else:
            local_pal = list(self._palette)

        for row in range(h):
            for col in range(w):
                pidx = pixel_indices[row * w + col]
                if pidx == 0:
                    continue  # palette entry 0 is transparent (matches hardware)
                # palette_offset shifts linearly and never wraps: an index
                # pushed past the palette is skipped, so an offset can
                # neither reach VOID nor alias back to a low colour.
                pidx += offset
                if pidx > 15:
                    continue
                r, g, b = local_pal[pidx]
                for dy in range(y_scale):
                    for dx in range(x_scale):
                        px = bx + col * x_scale + dx
                        py = by + row * y_scale + dy
                        if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                            self._display.putpixel((px, py), (r, g, b, 255))

    # ------------------------------------------------------------------ brightness / pan / power

    def set_brightness(self, value: int) -> None:
        level = int(value)
        if level < -2 or level > 2:
            raise ValueError("brightness level must be between -2 and 2")
        self._brightness_percent = _BRIGHTNESS_LEVEL_TO_PERCENT[level]

    def get_brightness(self) -> int:
        # Firmware maps only the exact percents back; anything else reads 0
        return _BRIGHTNESS_PERCENT_TO_LEVEL.get(self._brightness_percent, 0)

    def brightness(self, value: int | None = None) -> int | None:
        if value is None:
            return self._brightness_percent
        value = int(value)
        if value < 0 or value > 100:
            raise ValueError("Brightness must be 0-100")
        self._brightness_percent = value
        return None

    def set_pan(self, x: int, y: int) -> None:
        self._pan_x = max(-50, min(50, int(x)))
        self._pan_y = max(-50, min(50, int(y)))

    def get_pan(self) -> tuple[int, int]:
        return (self._pan_x, self._pan_y)

    def power_save(self, enable: object = None) -> bool | None:
        """Set power-save state, or return it (True = suspended) with no args.

        The emulator tracks the state but keeps rendering; on hardware a
        suspended panel shows nothing until ``power_save(false)``.
        """
        if enable is None:
            return self._suspended
        if not isinstance(enable, bool):
            raise ValueError("argument must be boolean")
        self._suspended = enable
        return None

    def width(self) -> int:
        return WIDTH

    def height(self) -> int:
        return HEIGHT
