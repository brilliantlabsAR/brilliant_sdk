from dataclasses import dataclass
import struct

@dataclass
class TxSpriteCoords:
    """
    A message containing sprite coordinates information for display.

    Attributes:
        code: Unsigned byte identifying the sprite code
        x: X-coordinate for sprite position (1..640)
        y: Y-coordinate for sprite position (1..400)
        offset: Palette offset value for the sprite (0..15)
    """
    code: int
    x: int
    y: int
    offset: int = 0

    def pack(self) -> bytes:
        """
        Packs the message into a binary format.

        Returns:
            bytes: Binary representation of the message in the format:
                  [code, x_msb, x_lsb, y_msb, y_lsb, offset]
        """
        # Pack the data using struct for consistent binary representation
        # B = unsigned char (1 byte)
        # >H = big-endian unsigned short (2 bytes)
        return struct.pack('>BHHB',
            self.code & 0xFF,     # 1 byte for sprite code
            self.x,               # 2 bytes for x
            self.y,               # 2 bytes for y
            self.offset & 0xFF    # 1 byte for offset
        )