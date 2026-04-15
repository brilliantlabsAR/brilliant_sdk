"""256×256 RGBA display framebuffer with PIL-based drawing."""
from __future__ import annotations

import threading
from typing import Sequence

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Named palette entries (0-indexed internally; Lua API exposes them as 1-16)
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

# Default palette RGB values matching typical Frame hardware defaults
_DEFAULT_PALETTE: list[tuple[int, int, int]] = [
    (0, 0, 0),        # 0 VOID
    (255, 255, 255),  # 1 WHITE
    (150, 150, 150),  # 2 GREY
    (215, 50, 35),    # 3 RED
    (230, 150, 170),  # 4 PINK
    (80, 40, 20),     # 5 DARKBROWN
    (140, 80, 50),    # 6 BROWN
    (230, 130, 30),   # 7 ORANGE
    (240, 220, 50),   # 8 YELLOW
    (20, 80, 20),     # 9 DARKGREEN
    (50, 180, 50),    # 10 GREEN
    (150, 230, 100),  # 11 LIGHTGREEN
    (15, 20, 100),    # 12 NIGHTBLUE
    (40, 100, 180),   # 13 SEABLUE
    (100, 180, 240),  # 14 SKYBLUE
    (200, 230, 255),  # 15 CLOUDBLUE
]

WIDTH = 256
HEIGHT = 256


def _rgb_from_int(color: int) -> tuple[int, int, int]:
    """Convert 0xRRGGBB integer to (r, g, b) tuple."""
    r = (color >> 16) & 0xFF
    g = (color >> 8) & 0xFF
    b = color & 0xFF
    return (r, g, b)


def _ycbcr_to_rgb(y: int, cb: int, cr: int) -> tuple[int, int, int]:
    """Convert 4-bit Y, 3-bit Cb, 3-bit Cr (hardware palette format) to RGB888."""
    # Scale to standard YCbCr ranges
    y_full = int(y / 15 * 255)
    cb_full = int(cb / 7 * 255) - 128
    cr_full = int(cr / 7 * 255) - 128
    r = max(0, min(255, int(y_full + 1.402 * cr_full)))
    g = max(0, min(255, int(y_full - 0.344136 * cb_full - 0.714136 * cr_full)))
    b = max(0, min(255, int(y_full + 1.772 * cb_full)))
    return (r, g, b)


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
        self._brightness: int = 0  # -2..2
        self._pan_x: int = 0
        self._pan_y: int = 0
        self._font: ImageFont.ImageFont | ImageFont.FreeTypeFont = ImageFont.load_default()

    # ------------------------------------------------------------------ palette

    def _resolve_index(self, index: int | str) -> int:
        """Resolve a palette index (1-based Lua int or named string) to 0-based."""
        if isinstance(index, str):
            name = index.upper()
            if name not in PALETTE_NAMES:
                raise ValueError(f"Unknown palette name: {index!r}")
            return PALETTE_NAMES[name]
        return int(index) - 1  # Lua uses 1-based

    def assign_color(self, index: int | str, r: int, g: int, b: int) -> None:
        i = self._resolve_index(index)
        self._palette[i] = (int(r), int(g), int(b))

    def assign_color_ycbcr(self, index: int | str, y: int, cb: int, cr: int) -> None:
        rgb = _ycbcr_to_rgb(int(y), int(cb), int(cr))
        self.assign_color(index, *rgb)

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
        px, py = int(x) - 1, int(y) - 1
        if 0 <= px < WIDTH and 0 <= py < HEIGHT:
            self._display.putpixel((px, py), rgb + (255,))

    def line(self, x0: int, y0: int, x1: int, y1: int, color: int) -> None:
        rgb = _rgb_from_int(int(color))
        self._draw.line([(int(x0) - 1, int(y0) - 1), (int(x1) - 1, int(y1) - 1)], fill=rgb + (255,))

    def rect(self, x: int, y: int, w: int, h: int, color: int, filled: bool = False) -> None:
        rgb = _rgb_from_int(int(color))
        x0, y0 = int(x) - 1, int(y) - 1
        x1, y1 = x0 + int(w) - 1, y0 + int(h) - 1
        if filled:
            self._draw.rectangle([x0, y0, x1, y1], fill=rgb + (255,))
        else:
            self._draw.rectangle([x0, y0, x1, y1], outline=rgb + (255,))

    def circle(self, cx: int, cy: int, r: int, color: int, filled: bool = False) -> None:
        rgb = _rgb_from_int(int(color))
        cx0, cy0 = int(cx) - 1, int(cy) - 1
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
        # Pair up into 0-based (x, y) tuples
        coords = [(flat[i] - 1, flat[i + 1] - 1) for i in range(0, len(flat) - 1, 2)]
        if len(coords) >= 2:
            self._draw.polygon(coords, fill=rgb + (255,))

    # ------------------------------------------------------------------ text / font

    def set_font(self, font_id: int, size: int = 16, scale: int = 1) -> None:
        # Use PIL default font; a future version could load real fonts from fonts/
        try:
            self._font = ImageFont.load_default(size=int(size))
        except TypeError:
            # Older Pillow versions don't accept size argument
            self._font = ImageFont.load_default()

    def get_font_list(self) -> list[dict]:
        return [{"id": 1, "name": "default"}]

    def text(self, txt: str, x: int, y: int, color: int = 0xFFFFFF) -> None:
        rgb = _rgb_from_int(int(color))
        self._draw.text((int(x) - 1, int(y) - 1), str(txt), fill=rgb + (255,), font=self._font)

    def char(self, codepoint: int, x: int, y: int, color: int = 0xFFFFFF) -> None:
        self.text(chr(int(codepoint)), x, y, color)

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

        fmt = int(color_format)
        offset = int(palette_offset)
        bx = int(x) - 1
        by = int(y) - 1
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
        else:
            # Palette-indexed: unpack pixels
            if fmt <= 2:
                pixel_indices = _unpack_1bit(raw)
            elif fmt <= 4:
                pixel_indices = _unpack_2bit(raw)
            else:
                pixel_indices = _unpack_4bit(raw)

            # Build palette for this bitmap (custom_palette_data overrides global)
            if custom_palette_data is not None:
                local_pal: list[tuple[int, int, int]] = []
                for i in range(len(custom_palette_data) // 3):
                    r = custom_palette_data[i * 3]
                    g = custom_palette_data[i * 3 + 1]
                    b = custom_palette_data[i * 3 + 2]
                    local_pal.append((r, g, b))
            else:
                # Build offset palette: index 0 always maps to palette[0]
                # (background/VOID stays black regardless of offset).
                # Indices 1-15 are shifted by palette_offset, wrapping within 1-15.
                n = len(self._palette)  # 16
                local_pal = [self._palette[0]] + [
                    self._palette[((i - 1 + offset) % (n - 1)) + 1]
                    for i in range(1, n)
                ]

            h = len(pixel_indices) // w
            for row in range(h):
                for col in range(w):
                    pidx = pixel_indices[row * w + col]
                    if pidx < len(local_pal):
                        r, g, b = local_pal[pidx]
                        for dy in range(y_scale):
                            for dx in range(x_scale):
                                px = bx + col * x_scale + dx
                                py = by + row * y_scale + dy
                                if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                                    self._display.putpixel((px, py), (r, g, b, 255))

    # ------------------------------------------------------------------ brightness / pan / power

    def set_brightness(self, value: int) -> None:
        self._brightness = max(-2, min(2, int(value)))

    def get_brightness(self) -> int:
        return self._brightness

    def brightness(self, value: int | None = None) -> int | None:
        if value is None:
            # Convert -2..2 scale to 0..100
            return int((self._brightness + 2) / 4 * 100)
        self._brightness = max(-2, min(2, int(value / 25) - 2))
        return None

    def set_pan(self, x: int, y: int) -> None:
        self._pan_x = max(-50, min(50, int(x)))
        self._pan_y = max(-50, min(50, int(y)))

    def get_pan(self) -> tuple[int, int]:
        return (self._pan_x, self._pan_y)

    def power_save(self, enable: bool) -> None:
        pass  # No-op in emulator

    def width(self) -> int:
        return WIDTH

    def height(self) -> int:
        return HEIGHT
