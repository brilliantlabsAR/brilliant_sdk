import io
import math
from abc import ABC, abstractmethod
from typing import List, Optional, Tuple

from PIL import Image, ImageDraw, ImageFont

from .tx_sprite import TxSprite

_MONOCHROME_PALETTE = bytes([0, 0, 0, 255, 255, 255])  # black, white


class TextLayout(ABC):
    """
    Defines the geometry of a text layout area, allowing different shapes
    (rectangles for Frame, circles for Halo's round display).

    Args:
        width: Layout area width in pixels
        height: Layout area height in pixels
        font_size: Font size in pixels
        font_family: Optional path or name of a TrueType font
        text_align: 'left', 'center' or 'right'
    """

    def __init__(
        self,
        width: int,
        height: int,
        font_size: int,
        font_family: Optional[str] = None,
        text_align: str = "left",
    ):
        self.width = width
        self.height = height
        self.font_size = font_size
        self.font_family = font_family
        self.text_align = text_align
        self._font = None

    @property
    def start_y(self) -> float:
        """The starting Y coordinate for laying out text."""
        return 0.0

    @abstractmethod
    def get_line_layout(self, line_y: float, line_height: float) -> Optional[Tuple[int, int]]:
        """
        Layout parameters (width, x_offset) for a line at a given Y position,
        or None if the line is outside the displayable area.
        """

    def get_font(self) -> ImageFont.FreeTypeFont:
        """The (cached) PIL font for this layout."""
        if self._font is None:
            if self.font_family:
                try:
                    self._font = ImageFont.truetype(self.font_family, self.font_size)
                except OSError:
                    self._font = ImageFont.load_default(self.font_size)
            else:
                self._font = ImageFont.load_default(self.font_size)
        return self._font


class RectangularTextLayout(TextLayout):
    """A standard rectangular text layout, e.g. for the Frame device."""

    def get_line_layout(self, line_y: float, line_height: float) -> Optional[Tuple[int, int]]:
        if line_y < 0 or line_y + line_height > self.height:
            return None
        return (self.width, 0)


class CircularTextLayout(TextLayout):
    """
    A circular text layout for Halo: text is constrained to a circle
    inscribed in the width/height box, inset by circle_margin.
    """

    def __init__(
        self,
        width: int,
        height: int,
        font_size: int,
        circle_margin: float = 15.0,
        font_family: Optional[str] = None,
        text_align: str = "center",
    ):
        super().__init__(width, height, font_size, font_family, text_align)
        self.circle_margin = circle_margin
        self.radius = min(width, height) / 2.0 - circle_margin
        self.center_x = width / 2.0
        self.center_y = height / 2.0

    @property
    def start_y(self) -> float:
        return self.center_y - self.radius

    def get_line_layout(self, line_y: float, line_height: float) -> Optional[Tuple[int, int]]:
        dist_from_center = (line_y + line_height / 2) - self.center_y

        if abs(dist_from_center) > self.radius:
            return None

        # Pythagoras: half-width of the chord at this y-position
        half_width = math.sqrt(self.radius**2 - dist_from_center**2)
        line_width = math.floor(half_width * 2)
        x_offset = math.floor(self.center_x - half_width)

        # Avoid very narrow lines near the top/bottom of the circle
        if line_width < self.font_size:
            return None

        return (line_width, x_offset)


class _LineData:
    """Measured information for a single line; width/x_offset are finalized during rasterization."""

    def __init__(self, text: str, width: int, x_offset: int, y_offset: int, line_height: int):
        self.text = text
        self.width = width
        self.x_offset = x_offset
        self.y_offset = y_offset
        self.line_height = line_height


class PageData:
    """A single measured page of text, ready to be rasterized into per-line sprites."""

    def __init__(self, lines: List[_LineData], layout: TextLayout):
        self._lines = lines
        self.layout = layout
        self._sprites: List[TxSprite] = []

    @property
    def is_empty(self) -> bool:
        return not self._lines

    @property
    def is_rasterized(self) -> bool:
        return bool(self._sprites)

    @property
    def rasterized_sprites(self) -> List[TxSprite]:
        return self._sprites

    @property
    def line_texts(self) -> List[str]:
        return [line.text for line in self._lines]

    def rasterize(self) -> None:
        """Rasterize the measured lines into one 1-bit TxSprite per line."""
        if self.is_rasterized:
            return

        font = self.layout.get_font()
        kept_lines = []

        for line in self._lines:
            if not line.text or line.line_height <= 0:
                continue

            text_width = math.ceil(font.getlength(line.text))
            if text_width <= 0:
                continue

            # Alignment offset within the measured line box; the sprite itself
            # is tight around the text and the offset is baked into x_offset.
            if self.layout.text_align == "center":
                align_offset = (line.width - text_width) / 2
            elif self.layout.text_align == "right":
                align_offset = line.width - text_width
            else:
                align_offset = 0.0

            img = Image.new("L", (text_width, line.line_height), 0)
            draw = ImageDraw.Draw(img)
            draw.text((0, 0), line.text, font=font, fill=255)

            pixels = bytes(1 if p >= 128 else 0 for p in img.getdata())

            line.x_offset = int(line.x_offset + align_offset)
            line.width = text_width
            kept_lines.append(line)

            self._sprites.append(
                TxSprite(
                    width=text_width,
                    height=line.line_height,
                    num_colors=2,
                    palette_data=_MONOCHROME_PALETTE,
                    pixel_data=pixels,
                )
            )

        self._lines = kept_lines

    def to_png_bytes(self) -> bytes:
        """A single PNG of the whole page, for debugging or verification."""
        if not self.is_rasterized:
            self.rasterize()

        page = Image.new("RGBA", (self.layout.width, self.layout.height), (0, 0, 0, 0))
        for line, sprite in zip(self._lines, self._sprites):
            line_img = Image.frombytes(
                "L", (sprite.width, sprite.height),
                bytes(255 if p else 0 for p in sprite.pixel_data),
            )
            page.paste(
                Image.merge("RGBA", (line_img,) * 3 + (line_img,)),
                (line.x_offset, line.y_offset),
            )

        buf = io.BytesIO()
        page.save(buf, format="PNG")
        return buf.getvalue()

    def pack(self) -> bytes:
        """
        Pack the page layout header for transmission:
        0xFF, width(u16), height(u16), num_lines(u8), then per line x(u16), y(u16).
        Byte-identical to the Flutter/WebBluetooth SDKs. Send this first, then
        each rasterized sprite's pack() on the same message code.
        """
        if not self.is_rasterized:
            raise Exception("Page must be rasterized before packing.")

        offsets = bytearray()
        for line in self._lines:
            offsets += bytes([
                (line.x_offset >> 8) & 0xFF,
                line.x_offset & 0xFF,
                (line.y_offset >> 8) & 0xFF,
                line.y_offset & 0xFF,
            ])

        return bytes([
            0xFF,
            (self.layout.width >> 8) & 0xFF,
            self.layout.width & 0xFF,
            (self.layout.height >> 8) & 0xFF,
            self.layout.height & 0xFF,
            len(self._sprites) & 0xFF,
        ]) + bytes(offsets)


class TxTextPage:
    """
    Lays out and rasterizes text into pages for any TextLayout shape.

    Unlike the Flutter SDK (where rasterization is async), all methods here
    are synchronous.
    """

    def __init__(self, layout: TextLayout, text: str):
        self.layout = layout
        self.text = text
        self._remaining_text = text.strip()

    @property
    def remaining_text(self) -> str:
        return self._remaining_text

    @property
    def has_more_text(self) -> bool:
        return bool(self._remaining_text)

    def measure_next_page(self) -> Optional[PageData]:
        """Measure the next page of text without rasterizing it."""
        if not self._remaining_text:
            return None

        font = self.layout.get_font()
        ascent, descent = font.getmetrics()
        actual_line_height = ascent + descent
        estimated_line_height = self.layout.font_size * 1.4

        lines: List[_LineData] = []
        text = self._remaining_text
        current_y = self.layout.start_y

        while text and current_y < self.layout.height:
            line_layout = self.layout.get_line_layout(current_y, estimated_line_height)
            if line_layout is None:
                break

            if current_y + actual_line_height > self.layout.height:
                break

            # Re-check with the actual height for better accuracy on circles
            final_layout = self.layout.get_line_layout(current_y, actual_line_height) or line_layout
            line_width, x_offset = final_layout

            end_index = self._break_index(text, font, line_width)
            line_text = text[:end_index].strip()

            if line_text:
                lines.append(
                    _LineData(line_text, line_width, x_offset, int(current_y), actual_line_height)
                )

            current_y += actual_line_height
            text = text[end_index:].lstrip()

        if not lines and self._remaining_text:
            # Not even one line fits this layout (e.g. it is smaller than a
            # line): drop the text so has_more_text turns False instead of
            # every call returning None forever
            self._remaining_text = ""
            return None

        self._remaining_text = text
        return PageData(lines, self.layout)

    def rasterize_next_page(self) -> Optional[PageData]:
        """Measure and rasterize the next page in one call."""
        page = self.measure_next_page()
        if page is not None:
            page.rasterize()
        return page

    @staticmethod
    def _break_index(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> int:
        """
        Index at which the first line of `text` breaks when constrained to
        max_width pixels: hard-breaks at newlines, prefers word boundaries,
        and always consumes at least one character.
        """
        newline = text.find("\n")
        segment = text[:newline] if newline != -1 else text

        if font.getlength(segment) <= max_width:
            # Whole segment fits; consume the newline too if there was one
            return len(segment) + (1 if newline != -1 else 0)

        # Binary search for the largest prefix that fits
        lo, hi = 1, len(segment)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if font.getlength(segment[:mid]) <= max_width:
                lo = mid
            else:
                hi = mid - 1
        end_index = lo

        # Prefer breaking at the previous space rather than mid-word
        if end_index < len(segment) and not segment[end_index].isspace():
            last_space = segment.rfind(" ", 0, end_index)
            if last_space > 0:
                return last_space + 1

        return end_index
