"""
Tests for TxTextPage, RectangularTextLayout and CircularTextLayout:
pack() byte layout (wire-compatible with the Flutter/WebBluetooth SDKs),
chord geometry, deterministic word wrapping, and rasterization.

Uses the bundled dogicapixel font so measurements don't vary by platform.
"""
import math
from pathlib import Path

import pytest

from brilliant_msg import (
    TxTextPage,
    RectangularTextLayout,
    CircularTextLayout,
)

FONT = str(Path(__file__).parent.parent / "examples" / "fonts" / "dogicapixel.ttf")


# ---------------------------------------------------------------------------
# Layout geometry
# ---------------------------------------------------------------------------

class TestRectangularTextLayout:
    def test_inside_bounds(self):
        layout = RectangularTextLayout(width=200, height=100, font_size=16)
        assert layout.get_line_layout(0, 20) == (200, 0)
        assert layout.get_line_layout(80, 20) == (200, 0)

    def test_outside_bounds(self):
        layout = RectangularTextLayout(width=200, height=100, font_size=16)
        assert layout.get_line_layout(-1, 20) is None
        assert layout.get_line_layout(81, 20) is None

    def test_start_y(self):
        layout = RectangularTextLayout(width=200, height=100, font_size=16)
        assert layout.start_y == 0.0


class TestCircularTextLayout:
    def test_geometry(self):
        layout = CircularTextLayout(width=256, height=256, font_size=16, circle_margin=15)
        assert layout.radius == 113.0
        assert layout.center_x == 128.0
        assert layout.center_y == 128.0
        assert layout.start_y == 15.0

    def test_chord_at_center_is_diameter(self):
        layout = CircularTextLayout(width=256, height=256, font_size=16, circle_margin=15)
        line_height = 20
        width, x_offset = layout.get_line_layout(128 - line_height / 2, line_height)
        assert width == 2 * 113
        assert x_offset == 128 - 113

    def test_chord_math(self):
        layout = CircularTextLayout(width=256, height=256, font_size=16, circle_margin=15)
        line_height = 20
        # line whose middle sits 60px above center
        line_y = 128 - 60 - line_height / 2
        width, x_offset = layout.get_line_layout(line_y, line_height)
        half = math.sqrt(113**2 - 60**2)
        assert width == math.floor(half * 2)
        assert x_offset == math.floor(128 - half)

    def test_outside_circle(self):
        layout = CircularTextLayout(width=256, height=256, font_size=16, circle_margin=15)
        assert layout.get_line_layout(-40, 20) is None
        assert layout.get_line_layout(280, 20) is None

    def test_narrow_chord_rejected(self):
        layout = CircularTextLayout(width=256, height=256, font_size=100, circle_margin=15)
        # near the top of the circle the chord is narrower than font_size
        assert layout.get_line_layout(15, 4) is None


# ---------------------------------------------------------------------------
# Measurement / word wrap
# ---------------------------------------------------------------------------

class TestMeasure:
    def test_word_wrap_and_consumption(self):
        layout = RectangularTextLayout(
            width=120, height=400, font_size=8, font_family=FONT
        )
        page = TxTextPage(layout, "the quick brown fox jumps over the lazy dog").measure_next_page()
        assert page is not None
        assert not page.is_empty
        # words are kept whole
        reassembled = " ".join(page.line_texts)
        assert reassembled == "the quick brown fox jumps over the lazy dog"
        assert len(page.line_texts) > 1

    def test_newlines_break_lines(self):
        layout = RectangularTextLayout(width=300, height=400, font_size=8, font_family=FONT)
        page = TxTextPage(layout, "one\ntwo\nthree").measure_next_page()
        assert page.line_texts == ["one", "two", "three"]

    def test_paging_consumes_all_text(self):
        layout = RectangularTextLayout(width=100, height=40, font_size=8, font_family=FONT)
        tx = TxTextPage(layout, "alpha beta gamma delta epsilon zeta eta theta " * 4)
        pages = []
        while tx.has_more_text:
            page = tx.measure_next_page()
            if page is None:
                break
            pages.append(page)
        assert len(pages) > 1
        assert not tx.has_more_text
        all_text = " ".join(t for p in pages for t in p.line_texts)
        assert all_text == ("alpha beta gamma delta epsilon zeta eta theta " * 4).strip()

    def test_empty_text(self):
        layout = RectangularTextLayout(width=100, height=100, font_size=8, font_family=FONT)
        tx = TxTextPage(layout, "")
        assert not tx.has_more_text
        assert tx.measure_next_page() is None

    def test_layout_too_small_for_one_line(self):
        # nothing fits: the text is dropped so a has_more_text loop terminates
        layout = RectangularTextLayout(width=100, height=4, font_size=8, font_family=FONT)
        tx = TxTextPage(layout, "hello world")
        assert tx.measure_next_page() is None
        assert not tx.has_more_text

    def test_long_word_char_broken(self):
        layout = RectangularTextLayout(width=60, height=200, font_size=8, font_family=FONT)
        tx = TxTextPage(layout, "supercalifragilisticexpialidocious")
        page = tx.measure_next_page()
        assert page is not None
        # the word is split across lines rather than dropped
        assert "".join(page.line_texts) == "supercalifragilisticexpialidocious"


# ---------------------------------------------------------------------------
# Rasterization and pack()
# ---------------------------------------------------------------------------

class TestRasterizeAndPack:
    def _page(self, text="hello world", **kwargs):
        defaults = dict(width=256, height=256, font_size=8, font_family=FONT)
        defaults.update(kwargs)
        layout = RectangularTextLayout(**defaults)
        return TxTextPage(layout, text).measure_next_page()

    def test_pack_requires_rasterize(self):
        page = self._page()
        with pytest.raises(Exception, match="rasterized"):
            page.pack()

    def test_rasterize_produces_monochrome_sprites(self):
        page = self._page()
        page.rasterize()
        assert page.is_rasterized
        assert len(page.rasterized_sprites) == len(page.line_texts)
        for sprite in page.rasterized_sprites:
            assert sprite.num_colors == 2
            assert sprite.palette_data == bytes([0, 0, 0, 255, 255, 255])
            assert set(sprite.pixel_data) <= {0, 1}
            assert 1 in sprite.pixel_data  # some text was actually drawn

    def test_pack_header_layout(self):
        page = self._page()
        page.rasterize()
        packed = page.pack()

        n = len(page.rasterized_sprites)
        assert packed[0] == 0xFF
        assert (packed[1] << 8 | packed[2]) == 256   # width
        assert (packed[3] << 8 | packed[4]) == 256   # height
        assert packed[5] == n                        # num lines
        assert len(packed) == 6 + 4 * n              # + per-line offsets

    def test_pack_offsets_match_lines(self):
        layout = CircularTextLayout(width=256, height=256, font_size=16, circle_margin=15)
        page = TxTextPage(layout, "some centered circular text for halo").measure_next_page()
        page.rasterize()
        packed = page.pack()

        n = packed[5]
        for i in range(n):
            base = 6 + 4 * i
            x = packed[base] << 8 | packed[base + 1]
            y = packed[base + 2] << 8 | packed[base + 3]
            line = page._lines[i]
            assert (x, y) == (line.x_offset, line.y_offset)
            # sprite must sit inside the circle's bounding box
            assert x >= layout.center_x - layout.radius - 1
            assert x + page.rasterized_sprites[i].width <= layout.center_x + layout.radius + 1

    def test_centered_alignment_offsets(self):
        layout = CircularTextLayout(
            width=256, height=256, font_size=8, circle_margin=15, font_family=FONT
        )
        page = TxTextPage(layout, "hi").measure_next_page()
        page.rasterize()
        sprite = page.rasterized_sprites[0]
        line = page._lines[0]
        # centered: sprite midpoint should be near the circle's center x
        mid = line.x_offset + sprite.width / 2
        assert abs(mid - 128) <= 2

    def test_to_png_bytes(self):
        page = self._page()
        png = page.to_png_bytes()
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
