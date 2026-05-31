from dataclasses import dataclass
import struct

@dataclass
class TxAutoExpSettings:
    """
    Message for auto exposure and gain settings.

    Attributes:
        metering_index: Zero-based index into ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'] i.e. 0, 1 or 2.
        exposure: Target exposure value (0.0-1.0)
        exposure_speed: Speed of exposure adjustments (0.0-1.0)
        shutter_limit: Maximum shutter value (4-16383)
        analog_gain_limit: Maximum analog gain value (1-248)
        white_balance_speed: Speed of white balance adjustments (0.0-1.0)
        rgb_gain_limit: Maximum gain value for red, green, blue channels (0-1023)
    """
    metering_index: int = 1
    exposure: float = 0.1
    exposure_speed: float = 0.45
    shutter_limit: int = 16383
    analog_gain_limit: int = 16
    white_balance_speed: float = 0.5
    rgb_gain_limit: int = 287

    def pack(self) -> bytes:
        """Pack the settings into 9 bytes."""
        return struct.pack('>BBBHBBH',
            self.metering_index & 0xFF,
            int(self.exposure * 255) & 0xFF,
            int(self.exposure_speed * 255) & 0xFF,
            self.shutter_limit & 0x3FFF,
            self.analog_gain_limit & 0xFF,
            int(self.white_balance_speed * 255) & 0xFF,
            self.rgb_gain_limit & 0x3FF
        )