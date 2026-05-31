from dataclasses import dataclass
import struct

@dataclass
class TxCaptureSettings:
    """
    Message for camera capture settings.

    Attributes:
        resolution: Image resolution (256-720, must be even)
        quality_index: Index into [VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH]
        pan: Image pan value (-140 to 140)
        raw: Whether to capture in RAW format
    """
    resolution: int = 512
    quality_index: int = 4
    pan: int = 0
    raw: bool = False

    def pack(self) -> bytes:
        """Pack the settings into 6 bytes."""
        half_res = self.resolution // 2
        pan_shifted = self.pan + 140

        return struct.pack('>BHHB',
            self.quality_index & 0xFF,
            half_res & 0xFFFF,
            pan_shifted & 0xFFFF,
            0x01 if self.raw else 0x00
        )