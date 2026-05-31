"""
Tests for TxSprite bit-packing, factory methods, TxImageSpriteBlock, and
TxTextSpriteBlock.

All tests are pure data-transformation tests — no BLE connection required.
"""
import io
import struct

import numpy as np
import pytest
from PIL import Image

from brilliant_msg import TxSprite, TxImageSpriteBlock, TxTextSpriteBlock


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_indexed_png(width: int, height: int, num_colors: int) -> bytes:
    """Create an indexed (mode 'P') PNG using the first *num_colors* palette slots."""
    img = Image.new('P', (width, height))
    # Build a palette with num_colors distinct colours (shades of red)
    palette: list[int] = []
    for i in range(num_colors):
        r = int(i * 255 / max(num_colors - 1, 1))
        palette.extend([r, 0, 0])
    palette.extend([0] * (768 - len(palette)))
    img.putpalette(palette)
    # Fill pixels cycling through all color indices so every index is used
    img.putdata([i % num_colors for i in range(width * height)])
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return buf.getvalue()


def _make_rgb_png(width: int, height: int) -> bytes:
    """Create a plain RGB PNG."""
    img = Image.new('RGB', (width, height), color=(128, 64, 32))
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return buf.getvalue()


def _make_colorful_rgb_png(width: int = 32, height: int = 32) -> bytes:
    """Create an RGB PNG with a colour gradient, ensuring many distinct colours
    are present so that quantize() produces a full 16-entry palette."""
    img = Image.new('RGB', (width, height))
    pixels = []
    for y in range(height):
        for x in range(width):
            r = int(x * 255 / max(width - 1, 1))
            g = int(y * 255 / max(height - 1, 1))
            b = (r + g) // 2
            pixels.append((r, g, b))
    img.putdata(pixels)
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return buf.getvalue()


def _make_sprite(width: int, height: int, num_colors: int,
                 pixels: list[int] | None = None) -> TxSprite:
    """Convenience: build a TxSprite directly from raw data."""
    palette = bytes(range(num_colors * 3))   # dummy RGB values
    if pixels is None:
        pixels = [i % num_colors for i in range(width * height)]
    return TxSprite(
        width=width,
        height=height,
        num_colors=num_colors,
        palette_data=palette,
        pixel_data=bytes(pixels),
        compress=False,
    )


# ---------------------------------------------------------------------------
# TxSprite.bpp
# ---------------------------------------------------------------------------

class TestTxSpriteBpp:
    def test_two_colors_is_1bpp(self):
        s = _make_sprite(1, 1, 2)
        assert s.bpp == 1

    def test_three_colors_is_2bpp(self):
        s = _make_sprite(1, 1, 3, pixels=[0])
        assert s.bpp == 2

    def test_four_colors_is_2bpp(self):
        s = _make_sprite(1, 1, 4, pixels=[0])
        assert s.bpp == 2

    def test_sixteen_colors_is_4bpp(self):
        s = _make_sprite(1, 1, 16, pixels=[0])
        assert s.bpp == 4


# ---------------------------------------------------------------------------
# TxSprite._pack_1bit
# ---------------------------------------------------------------------------

class TestPack1bit:
    def test_all_zeros(self):
        result = TxSprite._pack_1bit(bytes([0, 0, 0, 0, 0, 0, 0, 0]))
        assert result == bytes([0x00])

    def test_all_ones(self):
        result = TxSprite._pack_1bit(bytes([1, 1, 1, 1, 1, 1, 1, 1]))
        assert result == bytes([0xFF])

    def test_known_pattern(self):
        # [0,1,0,1,1,0,0,1] → 0b01011001 = 0x59
        result = TxSprite._pack_1bit(bytes([0, 1, 0, 1, 1, 0, 0, 1]))
        assert result == bytes([0x59])

    def test_partial_byte_pads_with_zeros(self):
        # 2 pixels → packed into 1 byte, 6 trailing zeros
        # [1, 0] → 0b10000000 = 0x80
        result = TxSprite._pack_1bit(bytes([1, 0]))
        assert result == bytes([0x80])

    def test_multiple_bytes(self):
        # 16 pixels → 2 bytes
        result = TxSprite._pack_1bit(bytes([1] * 16))
        assert result == bytes([0xFF, 0xFF])


# ---------------------------------------------------------------------------
# TxSprite._pack_2bit
# ---------------------------------------------------------------------------

class TestPack2bit:
    def test_four_colors_in_order(self):
        # [0,1,2,3] → each pair occupies 2 bits, MSB first per byte
        # byte 0: 00 01 10 11 = 0b00011011 = 0x1B
        result = TxSprite._pack_2bit(bytes([0, 1, 2, 3]))
        assert result == bytes([0x1B])

    def test_all_zeros(self):
        result = TxSprite._pack_2bit(bytes([0, 0, 0, 0]))
        assert result == bytes([0x00])

    def test_all_max(self):
        # [3,3,3,3] → 0b11111111 = 0xFF
        result = TxSprite._pack_2bit(bytes([3, 3, 3, 3]))
        assert result == bytes([0xFF])

    def test_eight_pixels_two_bytes(self):
        result = TxSprite._pack_2bit(bytes([0, 1, 2, 3, 3, 2, 1, 0]))
        assert len(result) == 2
        assert result[0] == 0x1B   # [0,1,2,3]
        assert result[1] == 0xE4   # [3,2,1,0]

    def test_partial_byte_padded(self):
        # 5 pixels → ceil(5/4) = 2 bytes; last 3 pixel slots of byte 2 are 0
        result = TxSprite._pack_2bit(bytes([1, 0, 0, 0, 3]))
        assert len(result) == 2
        # byte 0: [1,0,0,0] → 0b01000000 = 0x40
        # byte 1: [3,0,0,0] → 0b11000000 = 0xC0
        assert result[0] == 0x40
        assert result[1] == 0xC0


# ---------------------------------------------------------------------------
# TxSprite._pack_4bit
# ---------------------------------------------------------------------------

class TestPack4bit:
    def test_two_nibbles(self):
        # [0xA, 0xB] → high nibble first: 0xAB
        result = TxSprite._pack_4bit(bytes([0xA, 0xB]))
        assert result == bytes([0xAB])

    def test_all_zeros(self):
        result = TxSprite._pack_4bit(bytes([0, 0]))
        assert result == bytes([0x00])

    def test_all_max_nibble(self):
        result = TxSprite._pack_4bit(bytes([15, 15]))
        assert result == bytes([0xFF])

    def test_four_pixels_two_bytes(self):
        # [0xA, 0xB, 0x0, 0xF] → [0xAB, 0x0F]
        result = TxSprite._pack_4bit(bytes([0xA, 0xB, 0x0, 0xF]))
        assert result == bytes([0xAB, 0x0F])

    def test_odd_pixel_count_padded(self):
        # 3 pixels → 2 bytes, last nibble of byte 2 is 0
        result = TxSprite._pack_4bit(bytes([0x1, 0x2, 0x3]))
        assert len(result) == 2
        assert result[0] == 0x12
        assert result[1] == 0x30   # 0x3 in high nibble, 0 in low


# ---------------------------------------------------------------------------
# TxSprite.pack() — header and palette
# ---------------------------------------------------------------------------

class TestTxSpritePackHeader:
    def test_header_is_7_bytes(self):
        s = _make_sprite(4, 4, 2)
        data = s.pack()
        # 7-byte header + palette + pixels
        assert len(data) >= 7

    def test_header_fields(self):
        s = _make_sprite(8, 4, 4)
        data = s.pack()
        w, h, compress, bpp, nc = struct.unpack('>HHBBB', data[:7])
        assert w == 8
        assert h == 4
        assert compress == 0
        assert bpp == 2       # 4 colors → 2 bpp
        assert nc == 4

    def test_palette_follows_header(self):
        palette = bytes([255, 0, 0,  0, 255, 0])  # red, green
        s = TxSprite(width=1, height=2, num_colors=2,
                     palette_data=palette, pixel_data=bytes([0, 1]))
        data = s.pack()
        assert data[7:13] == palette

    def test_compress_flag_in_header(self):
        s = _make_sprite(2, 2, 2)
        s.compress = True
        data = s.pack()
        _, _, compress, _, _ = struct.unpack('>HHBBB', data[:7])
        assert compress == 1

    def test_1bpp_sprite_total_size(self):
        # width=8, height=1, 2 colors: 7 header + 6 palette + 1 packed byte = 14
        palette = bytes([0, 0, 0,  255, 255, 255])
        pixels = bytes([0, 1, 0, 1, 0, 1, 0, 1])
        s = TxSprite(width=8, height=1, num_colors=2,
                     palette_data=palette, pixel_data=pixels)
        assert len(s.pack()) == 7 + 6 + 1

    def test_lz4_compression_applied_when_enabled(self):
        import lz4.frame
        palette = bytes([0]*3 + [255]*3)
        pixels = bytes([0, 1] * 8)   # 16 pixels, 1-bit packing → 2 bytes
        s = TxSprite(width=16, height=1, num_colors=2,
                     palette_data=palette, pixel_data=pixels, compress=True)
        data = s.pack()
        packed_region = data[7 + 6:]
        # Verify the packed region is valid LZ4 data
        decompressed = lz4.frame.decompress(packed_region)
        assert len(decompressed) == 2  # 16 pixels @ 1 bpp = 2 bytes


# ---------------------------------------------------------------------------
# TxSprite.from_indexed_png_bytes
# ---------------------------------------------------------------------------

class TestFromIndexedPngBytes:
    def test_2_color_png_round_trip(self):
        png = _make_indexed_png(4, 4, 2)
        s = TxSprite.from_indexed_png_bytes(png)
        assert s.num_colors == 2
        assert s.width == 4
        assert s.height == 4
        assert len(s.palette_data) == 6   # 2 × RGB

    def test_16_color_png(self):
        png = _make_indexed_png(4, 4, 16)
        s = TxSprite.from_indexed_png_bytes(png)
        assert s.num_colors == 16
        assert len(s.palette_data) == 48  # 16 × RGB

    def test_non_indexed_raises_value_error(self):
        png = _make_rgb_png(4, 4)
        with pytest.raises(ValueError, match="indexed"):
            TxSprite.from_indexed_png_bytes(png)

    def test_more_than_16_colors_raises_value_error(self):
        png = _make_indexed_png(17, 1, 17)
        with pytest.raises(ValueError, match="16 colors"):
            TxSprite.from_indexed_png_bytes(png)

    def test_pixel_count_matches_dimensions(self):
        png = _make_indexed_png(6, 8, 4)
        s = TxSprite.from_indexed_png_bytes(png)
        assert len(s.pixel_data) == 6 * 8

    def test_oversized_image_is_resized(self):
        # Create a large indexed image that exceeds 640×400
        img = Image.new('P', (800, 600))
        palette = [0, 0, 0,  255, 255, 255] + [0] * (768 - 6)
        img.putpalette(palette)
        img.putdata([i % 2 for i in range(800 * 600)])
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        s = TxSprite.from_indexed_png_bytes(buf.getvalue())
        assert s.width <= 640
        assert s.height <= 400


# ---------------------------------------------------------------------------
# TxSprite.from_image_bytes
# ---------------------------------------------------------------------------

class TestFromImageBytes:
    def test_returns_16_color_sprite(self):
        png = _make_rgb_png(32, 32)
        s = TxSprite.from_image_bytes(png)
        assert s.num_colors == 16

    def test_palette_is_48_bytes(self):
        # Use a colourful gradient so quantize() produces a full 16-entry palette
        s = TxSprite.from_image_bytes(_make_colorful_rgb_png())
        assert len(s.palette_data) == 48

    def test_first_palette_entry_is_black(self):
        # from_image_bytes forces palette[0] to black (for transparency)
        s = TxSprite.from_image_bytes(_make_rgb_png(16, 16))
        assert s.palette_data[0:3] == bytes([0, 0, 0])

    def test_dimensions_within_bounds(self):
        # Start with a very large image; should be scaled down
        img = Image.new('RGB', (1000, 1000), color=(100, 150, 200))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        s = TxSprite.from_image_bytes(buf.getvalue())
        assert s.width <= 640
        assert s.height <= 400

    def test_pixel_count_matches_dimensions(self):
        s = TxSprite.from_image_bytes(_make_rgb_png(20, 10))
        assert len(s.pixel_data) == s.width * s.height

    def test_palette_always_48_bytes_for_uniform_image(self):
        """Solid-colour input (1 unique colour) must still yield a 48-byte palette."""
        s = TxSprite.from_image_bytes(_make_rgb_png(16, 16))   # solid (128,64,32)
        assert len(s.palette_data) == 48

    def test_palette_always_48_bytes_for_two_color_image(self):
        """An image with only 2 distinct colours must still yield a 48-byte palette."""
        img = Image.new('RGB', (16, 16))
        half = 16 * 8
        img.putdata([(255, 0, 0)] * half + [(0, 0, 255)] * half)
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        s = TxSprite.from_image_bytes(buf.getvalue())
        assert len(s.palette_data) == 48


# ---------------------------------------------------------------------------
# TxImageSpriteBlock
# ---------------------------------------------------------------------------

class TestTxImageSpriteBlock:
    def test_pack_header_length(self):
        image = _make_sprite(8, 16, 4)
        block = TxImageSpriteBlock(image, sprite_line_height=8)
        assert len(block.pack()) == 9  # B + H + H + H + B + B

    def test_pack_header_fields(self):
        image = _make_sprite(8, 16, 4)
        block = TxImageSpriteBlock(image, sprite_line_height=8,
                                   progressive_render=True, updatable=False)
        data = block.pack()
        marker, w, h, lh, prog, upd = struct.unpack('>BHHHBB', data)
        assert marker == 0xFF
        assert w == 8
        assert h == 16
        assert lh == 8
        assert prog == 1
        assert upd == 0

    def test_even_split_into_lines(self):
        # 16-pixel-high image split into 4-pixel lines → 4 lines
        image = _make_sprite(4, 16, 2)
        block = TxImageSpriteBlock(image, sprite_line_height=4)
        assert len(block.sprite_lines) == 4

    def test_uneven_split_has_partial_final_line(self):
        # 10-pixel-high image, 4-pixel lines → 2 full + 1 partial (2 px)
        image = _make_sprite(4, 10, 2)
        block = TxImageSpriteBlock(image, sprite_line_height=4)
        assert len(block.sprite_lines) == 3
        assert block.sprite_lines[-1].height == 2

    def test_line_sprites_share_palette(self):
        image = _make_sprite(4, 8, 4)
        block = TxImageSpriteBlock(image, sprite_line_height=4)
        for line in block.sprite_lines:
            assert line.palette_data == image.palette_data

    def test_line_sprites_have_correct_width(self):
        image = _make_sprite(12, 8, 2)
        block = TxImageSpriteBlock(image, sprite_line_height=4)
        for line in block.sprite_lines:
            assert line.width == 12

    def test_compressed_line_height_auto_calculated(self):
        # For compressed 4-bpp (16 colors), 4096-byte limit per row
        image = _make_sprite(8, 32, 16)
        image.compress = True
        block = TxImageSpriteBlock(image)
        # packed_bytes_per_row = ceil(8 / (8/4)) = ceil(8/2) = 4
        # sprite_line_height = 4096 // 4 = 1024
        assert block.sprite_line_height == 1024


# ---------------------------------------------------------------------------
# TxTextSpriteBlock
# ---------------------------------------------------------------------------

class TestTxTextSpriteBlock:
    def test_pack_length(self):
        block = TxTextSpriteBlock()
        assert len(block.pack()) == 6

    def test_pack_header_fields(self):
        block = TxTextSpriteBlock(width=320, line_height=24, max_display_lines=5)
        data = block.pack()
        assert data[0] == 0xFF   # block marker
        assert struct.unpack('>H', data[1:3])[0] == 320
        assert struct.unpack('>H', data[3:5])[0] == 24
        assert data[5] == 5

    def test_create_text_sprites_returns_list(self):
        block = TxTextSpriteBlock(width=200, line_height=16, max_display_lines=3)
        sprites = block.create_text_sprites("Hello\nWorld")
        assert isinstance(sprites, list)
        assert len(sprites) > 0

    def test_each_sprite_is_two_color(self):
        block = TxTextSpriteBlock(width=200, line_height=16, max_display_lines=3)
        for sprite in block.create_text_sprites("Test"):
            assert sprite.num_colors == 2
            assert len(sprite.palette_data) == 6

    def test_palette_is_black_and_white(self):
        block = TxTextSpriteBlock()
        for sprite in block.create_text_sprites("A"):
            assert sprite.palette_data[0:3] == bytes([0, 0, 0])     # black
            assert sprite.palette_data[3:6] == bytes([255, 255, 255])  # white

    def test_empty_string_returns_no_sprites(self):
        block = TxTextSpriteBlock()
        assert block.create_text_sprites("") == []
