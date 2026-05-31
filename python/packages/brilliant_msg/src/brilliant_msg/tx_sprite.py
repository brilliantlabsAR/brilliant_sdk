from dataclasses import dataclass
import struct
import numpy as np
from PIL import Image
import io
import lz4.frame

@dataclass
class TxSprite:
    """
    A sprite message containing image data with a custom palette.

    Attributes:
        width: Width of the sprite in pixels
        height: Height of the sprite in pixels
        num_colors: Number of colors in the palette (2, 4, or 16)
        palette_data: RGB values for each color (3 bytes per color)
        pixel_data: Array of palette indices for each pixel
    """
    width: int
    height: int
    num_colors: int
    palette_data: bytes
    pixel_data: bytes
    compress: bool = False

    @staticmethod
    def from_indexed_png_bytes(image_bytes: bytes, compress=False) -> 'TxSprite':
        """Create a TxSprite from an indexed PNG with minimal processing."""
        img = Image.open(io.BytesIO(image_bytes))

        if img.mode != 'P' or len(img.getcolors()) > 16:
            raise ValueError("PNG must be indexed with a palette of 16 colors or fewer.")

        # Resize if needed while preserving aspect ratio
        if img.width > 640 or img.height > 400:
            img.thumbnail((640, 400), Image.Resampling.NEAREST)

        # Extract palette data (only RGB, discarding alpha if present)
        raw_palette = img.getpalette()
        # Determine palette size from the PNG bit depth when it's explicitly encoded
        # (1–4 bits). Pillow may omit or set bits=8 for programmatically-created palette
        # PNGs (e.g. via putpalette), so fall back to the minimum valid palette size
        # that covers all unique pixel indices reported by getcolors().
        bits = img.info.get('bits')
        if bits is not None and 1 <= bits <= 4:
            num_colors = 2 ** bits
        else:
            n_used = len(img.getcolors())
            if n_used <= 2:
                num_colors = 2
            elif n_used <= 4:
                num_colors = 4
            else:
                num_colors = 16
        palette_data = bytes(raw_palette[:num_colors * 3])  # Keep only RGB values

        # Extract pixel data
        pixel_data = np.array(img)

        return TxSprite(
            width=img.width,
            height=img.height,
            num_colors=num_colors,
            palette_data=palette_data,
            pixel_data=pixel_data.tobytes(),
            compress=compress
        )

    @staticmethod
    def from_image_bytes(image_bytes: bytes, max_pixels = 48000, compress=False) -> 'TxSprite':
        """
        Create a sprite from the bytes of any image file format supported by PIL Image.open(),
        quantizing and scaling to ensure it fits within max_pixels (e.g. 48,000 pixels).
        """
        img = Image.open(io.BytesIO(image_bytes))

        # Convert to RGB mode if not already
        if img.mode != 'RGB':
            img = img.convert('RGB')

        # Calculate new size to fit within max_pixels while maintaining aspect ratio
        img_pixels = img.width * img.height
        if img_pixels > max_pixels:
            scale_factor = (max_pixels / img_pixels) ** 0.5
            new_width = int(img.width * scale_factor)
            new_height = int(img.height * scale_factor)
            img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)

        # Ensure the image does not exceed 640x400 after initial scaling
        if img.width > 640 or img.height > 400:
            img.thumbnail((640, 400), Image.Resampling.NEAREST)

        # Quantize to 16 colors if needed
        if img.mode != 'P' or img.getcolors() is None or len(img.getcolors()) > 16:
            img = img.quantize(colors=16, method=Image.Quantize.MEDIANCUT)

        # Get first 16 RGB colors from the palette, padding unused slots to zero.
        # Pillow 10+ returns only the colours actually present in the quantized image
        # rather than always padding to 256 entries, so images with fewer than 16
        # unique colours would otherwise produce a short palette list.
        palette = list(img.getpalette()[:48])
        palette.extend([0] * (48 - len(palette)))
        pixel_data = np.array(img)

        # The quantized palette comes back in a luminance gradient from lightest to darkest.
        # Ensure the darkest is at index 0 by swapping index 0 with index 15
        palette[0:3], palette[45:48] = palette[45:48], palette[0:3]

        # Update the pixel_data accordingly
        pixel_data[pixel_data == 0] = 255  # Temporary value to avoid conflict
        pixel_data[pixel_data == 15] = 0
        pixel_data[pixel_data == 255] = 15

        # Set the first (darkest, not necessarily black) entry in the palette to black for transparency
        palette[0:3] = 0, 0, 0

        return TxSprite(
            width=img.width,
            height=img.height,
            num_colors=16,
            palette_data=bytes(palette),
            pixel_data=pixel_data.tobytes(),
            compress=compress
        )

    @property
    def bpp(self) -> int:
        """Bits per pixel based on the number of colors."""
        if self.num_colors <= 2:
            return 1
        elif self.num_colors <= 4:
            return 2
        elif self.num_colors <= 16:
            return 4
        else:
            raise ValueError(f"num_colors must be equal to or less than 16: {self.num_colors}")

    def pack(self) -> bytes:
        """Pack the sprite into its binary format."""
        # Calculate bits per pixel based on number of colors
        if self.num_colors <= 2:
            bpp = 1
            pack_func = self._pack_1bit
        elif self.num_colors <= 4:
            bpp = 2
            pack_func = self._pack_2bit
        else:
            bpp = 4
            pack_func = self._pack_4bit

        # Pack pixel data
        packed_pixels = pack_func(self.pixel_data)

        # Create header
        header = struct.pack('>HHBBB',
            self.width,
            self.height,
            int(self.compress),
            bpp,
            self.num_colors
        )

        if self.compress:
            packed_pixels = lz4.frame.compress(packed_pixels, compression_level=9)

        return header + self.palette_data + packed_pixels

    @staticmethod
    def _pack_1bit(data: bytes) -> bytes:
        """Pack 1-bit pixels (2 colors) into bytes."""
        data_array = np.frombuffer(data, dtype=np.uint8)
        packed = np.packbits(data_array)
        return packed.tobytes()

    @staticmethod
    def _pack_2bit(data: bytes) -> bytes:
        """Pack 2-bit pixels (4 colors) into bytes."""
        data_array = np.frombuffer(data, dtype=np.uint8)
        packed = np.zeros(len(data_array) // 4 + (1 if len(data_array) % 4 else 0), dtype=np.uint8)

        for i in range(0, len(data_array)):
            byte_idx = i // 4
            bit_offset = (3 - (i % 4)) * 2
            packed[byte_idx] |= (data_array[i] & 0x03) << bit_offset

        return packed.tobytes()

    @staticmethod
    def _pack_4bit(data: bytes) -> bytes:
        """Pack 4-bit pixels (16 colors) into bytes."""
        data_array = np.frombuffer(data, dtype=np.uint8)
        packed = np.zeros(len(data_array) // 2 + (1 if len(data_array) % 2 else 0), dtype=np.uint8)

        for i in range(0, len(data_array)):
            byte_idx = i // 2
            bit_offset = (1 - (i % 2)) * 4
            packed[byte_idx] |= (data_array[i] & 0x0F) << bit_offset

        return packed.tobytes()
