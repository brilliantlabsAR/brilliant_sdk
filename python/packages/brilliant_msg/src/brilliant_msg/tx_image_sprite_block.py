import struct
from typing import List
import numpy as np
from .tx_sprite import TxSprite

class TxImageSpriteBlock:
    """
    An image split into horizontal sprite strips.

    Attributes:
        image: Source sprite to split
        sprite_line_height: Height of each sprite strip. If the TxSprite is compressed, the strip has a packed size limit of 4kB and this value is ignored.
        progressive_render: Whether to render lines as they arrive
        updatable: Whether lines can be updated after initial render
    """
    image: TxSprite
    sprite_line_height: int
    progressive_render: bool
    updatable: bool

    def __init__(self, image: TxSprite, sprite_line_height: int = 16, progressive_render: bool = True, updatable: bool = True):
        self.image = image
        self.progressive_render = progressive_render
        self.updatable = updatable
        if image.compress:
            # 4k uncompressed (binary packed) limit
            packed_bytes_per_row = int((image.width + (8 / image.bpp) - 1) // (8 / image.bpp))
            self.sprite_line_height = int(4096 // packed_bytes_per_row)
        else:
            self.sprite_line_height = sprite_line_height

        self.sprite_lines: List[TxSprite] = []
        self._split_into_lines()

    def _split_into_lines(self):
        """Split the source image into horizontal strips."""
        pixels = np.frombuffer(self.image.pixel_data, dtype=np.uint8)
        pixels = pixels.reshape((self.image.height, self.image.width))

        # Process full-height lines
        for i in range(0, self.image.height // self.sprite_line_height):
            start_y = i * self.sprite_line_height
            line_pixels = pixels[start_y:start_y + self.sprite_line_height]

            self.sprite_lines.append(TxSprite(
                width=self.image.width,
                height=self.sprite_line_height,
                num_colors=self.image.num_colors,
                palette_data=self.image.palette_data,
                pixel_data=line_pixels.tobytes(),
                compress=self.image.compress
            ))

        # Process final partial line if any
        remaining_height = self.image.height % self.sprite_line_height
        if remaining_height > 0:
            final_line = pixels[-remaining_height:]
            self.sprite_lines.append(TxSprite(
                width=self.image.width,
                height=remaining_height,
                num_colors=self.image.num_colors,
                palette_data=self.image.palette_data,
                pixel_data=final_line.tobytes(),
                compress=self.image.compress
            ))

    def pack(self) -> bytes:
        """Pack the image block header."""
        if not self.sprite_lines:
            raise Exception("No sprite lines to pack")

        return struct.pack('>BHHHBB',
            0xFF,  # Block marker
            self.image.width,
            self.image.height,
            self.sprite_line_height,
            1 if self.progressive_render else 0,
            1 if self.updatable else 0
        )