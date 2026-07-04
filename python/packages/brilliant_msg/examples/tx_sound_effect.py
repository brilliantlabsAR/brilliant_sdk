import struct
from dataclasses import dataclass

@dataclass
class TxSoundEffect:
    """
    A message directing the frameside app to play one of the firmware's
    built-in sfxr sound effect presets (pickup, laser, explosion, powerup,
    hit, jump, blip) via frame.sound.play().
    The same effect and seed always reproduce the same sound.
    """
    # firmware sound preset name, e.g. 'jump'
    effect: str
    # 32-bit seed for the sound generator
    seed: int

    def pack(self) -> bytes:
        """Pack the message as a big-endian Uint32 seed followed by the preset name."""
        return struct.pack('>I', self.seed & 0xFFFFFFFF) + self.effect.encode()
