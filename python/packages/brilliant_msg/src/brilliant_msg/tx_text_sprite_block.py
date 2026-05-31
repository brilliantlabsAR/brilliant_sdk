from dataclasses import dataclass
from typing import List, Optional
from PIL import Image, ImageDraw, ImageFont
from .tx_sprite import TxSprite

@dataclass
class TxTextSpriteBlock:
    """
    A block of text rendered as sprites.

    Attributes:
        width: Width constraint for text layout
        line_height: Height of each line in pixels
        font_size: Font size in pixels
        max_display_lines: Maximum number of lines to display
        font_family: Optional font family name
    """
    width: int = 200
    line_height: int = 16
    font_size: int = 12
    max_display_lines: int = 3
    text: str = "" # deprecated, use create_text_sprites directly
    font_family: Optional[str] = None

    def create_text_sprites(self, text: str) -> List[TxSprite]:
        """Create sprites from rendered text."""
        sprites: List[TxSprite] = []
        # Create image large enough for text
        img = Image.new('RGB', (self.width, self.line_height * self.max_display_lines), 'black')
        draw = ImageDraw.Draw(img)

        # Try to load specified font or use default
        try:
            font = ImageFont.truetype(self.font_family, self.font_size) if self.font_family else \
                   ImageFont.load_default()
        except OSError:
            font = ImageFont.load_default()

        # Draw text and split into lines
        lines = []
        y = 0
        for line in text.split('\n'):
            bbox = draw.textbbox((0, y), line, font=font)
            if bbox[3] - bbox[1] > 0:  # If line has height
                draw.text((0, y), line, font=font, fill='white')
                lines.append((bbox[0], y, bbox[2], bbox[3]))
            y += self.line_height

        # Convert each line to a sprite
        for left, top, right, bottom in lines:
            line_img = img.crop((left, top, right, bottom))

            # Convert to TxSprite with 2-color palette
            sprite = TxSprite(
                width=line_img.width,
                height=line_img.height,
                num_colors=2,
                palette_data=bytes([0,0,0, 255,255,255]),  # Black and white
                pixel_data=bytes(1 if p[0] > 127 else 0 for p in line_img.getdata())
            )
            sprites.append(sprite)
        return sprites

    def pack(self) -> bytes:
        """Pack the text block header."""
        return bytes([
            0xFF,  # Block marker
            self.width >> 8,
            self.width & 0xFF,
            self.line_height >> 8,
            self.line_height & 0xFF,
            self.max_display_lines & 0xFF,
        ])
