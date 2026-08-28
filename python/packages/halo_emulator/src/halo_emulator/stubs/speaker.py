"""frame.speaker.* stubs — no audio output, firmware-faithful validation.

Mirrors firmware 0.8.9 lua_speaker.c: start() config validation including
the per-stream `gain` and `budget` loudness fields added in 0.8.9, volume()
getter/setter semantics, play() stream-state checks. No audio is produced.
"""
from __future__ import annotations

from typing import Any


class SpeakerStub:
    def __init__(self) -> None:
        self._volume: int = 50
        self._streaming: bool = False

    def start(self, cfg: Any = None) -> None:
        # start() while streaming is a legal stop-and-reconfigure on firmware
        if cfg is None:
            raise ValueError("Expected a configuration table")

        def opt(name: str, default: Any) -> Any:
            try:
                val = getattr(cfg, name)
            except AttributeError:
                return default
            return default if val is None else val

        # Firmware treats any encoder other than "lc3" as pcm — no validation
        use_lc3 = str(opt("encoder", "pcm")) == "lc3"

        sample_rate = int(opt("sample_rate", 8000))
        if sample_rate not in (8000, 16000):
            raise ValueError("Sample rate must be 8000 or 16000")

        channels = int(opt("channels", 1))
        if channels not in (1, 2):
            raise ValueError("Channels must be 1 or 2")

        bit_depth = int(opt("bit_depth", 16))
        if bit_depth != 16:
            raise ValueError("Bit depth must be 16")

        if use_lc3:
            duration = int(opt("duration", 1000))
            if duration not in (750, 1000):
                raise ValueError("LC3 duration must be 750 or 1000")
            bitrate = int(opt("bitrate", 16000))
            if bitrate % 8000 != 0 or bitrate > 96000:
                raise ValueError("Bitrate must be multiple of 8000 and <= 96000")

        volume = int(opt("volume", 50))
        if not 0 <= volume <= 100:
            raise ValueError("Volume must be 0-100")

        gain = int(opt("gain", 0))
        if not 0 <= gain <= 12:
            raise ValueError("Gain must be 0-12 dB")

        budget = int(opt("budget", 0))
        if budget != 0 and not 10 <= budget <= 100:
            raise ValueError("Budget must be 10-100")

        self._volume = volume
        self._streaming = True

    def play(self, data: Any = None) -> None:
        if not isinstance(data, (str, bytes)):
            raise ValueError("Expected audio data as a string")
        if not self._streaming:
            raise ValueError("Speaker not started")
        # empty data returns cleanly on firmware; audio itself is not emulated

    def volume(self, val: int | None = None) -> int | None:
        if val is None:
            return self._volume
        if not self._streaming:
            raise ValueError("Speaker not initialized")
        val = int(val)
        if not 0 <= val <= 100:
            raise ValueError("Volume must be 0-100")
        self._volume = val
        return None

    def stop(self) -> None:
        # no-op when already stopped, as on firmware
        self._streaming = False
