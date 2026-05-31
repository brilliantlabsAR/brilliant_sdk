from dataclasses import dataclass
import struct

@dataclass
class TxPlainText:
    """
    A message containing plain text with positioning and formatting information.

    Attributes:
        text: The plain text content to be transmitted
        x: X-coordinate for text position (1-640, Lua/1-based indexing)
        y: Y-coordinate for text position (1-400, Lua/1-based indexing)
        palette_offset: Color palette offset (1-15, 0/'VOID' is invalid)
        spacing: Character spacing value
    """
    text: str
    x: int = 1
    y: int = 1
    palette_offset: int = 1
    spacing: int = 4

    def pack(self) -> bytes:
        """
        Packs the message into a binary format.

        Returns:
            bytes: Binary representation of the message in the format:
                  [x_msb, x_lsb, y_msb, y_lsb, palette_offset, spacing, text_bytes...]
        """
        # Convert text to UTF-8 bytes
        text_bytes = self.text.encode('utf-8')

        # Pack the header using struct for consistent binary representation
        # >H = big-endian unsigned short (2 bytes)
        # B = unsigned char (1 byte)
        header = struct.pack('>HHBB',
            self.x,            # 2 bytes for x
            self.y,            # 2 bytes for y
            self.palette_offset & 0x0F,  # 1 byte for palette (masked to 4 bits)
            self.spacing & 0xFF          # 1 byte for spacing
        )

        # Combine header and text bytes
        return header + text_bytes
