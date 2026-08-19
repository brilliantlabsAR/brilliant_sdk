"""frame.microphone.* stubs — no audio capture, full API surface.

Mirrors firmware 0.8.8 lua_microphone.c: start() config validation,
strictly non-blocking read() semantics (nil when stopped, "" when no data,
partial reads), status(), aec()/voice() toggles and diag().
Feed test audio in with HaloEmulator.inject_microphone_data().
"""
from __future__ import annotations

import threading
from typing import Any, Callable


class MicrophoneStub:
    def __init__(self) -> None:
        self._runtime: Any = None  # lupa runtime, set by build_lua_runtime
        self._gain: int = 0
        self._aad_cb: Callable | None = None
        self._streaming: bool = False
        self._aec: bool = False
        self._voice: bool = False
        self._buffer = bytearray()
        self._buffer_lock = threading.Lock()

    def start(self, cfg: Any = None) -> None:
        def opt(name: str, default: Any) -> Any:
            if cfg is None:
                return default
            try:
                val = getattr(cfg, name)
            except AttributeError:
                return default
            return default if val is None else val

        sample_rate = int(opt("sample_rate", 8000))
        bit_depth = int(opt("bit_depth", 16))
        channels = int(opt("channels", 1))
        encoder = str(opt("encoder", "pcm"))
        duration = int(opt("duration", 1000))
        bitrate = int(opt("bitrate", 16000))
        gain = int(opt("gain", 0))

        if sample_rate not in (8000, 16000):
            raise ValueError("Sample rate must be 8000 or 16000")
        if bit_depth not in (8, 16):
            raise ValueError("Bit depth must be 8 or 16")
        if channels not in (1, 2):
            raise ValueError("Channels must be 1 or 2")
        if encoder not in ("pcm", "lc3"):
            raise ValueError("Encoder must be 'pcm' or 'lc3'")
        if encoder == "lc3":
            if duration not in (750, 1000):
                raise ValueError("LC3 duration must be 750 or 1000")
            if bitrate % 8000 != 0 or bitrate > 96000:
                raise ValueError("LC3 bitrate must be a multiple of 8000 and at most 96000")
        if not -10 <= gain <= 10:
            raise ValueError("Gain must be between -10 and 10")

        self._gain = gain
        aec = opt("aec", None)
        if aec is not None:
            self._aec = bool(aec)
        voice = opt("voice", None)
        if voice is not None:
            self._voice = bool(voice)
        self._streaming = True

    def read(self, byte_count: int) -> str | None:
        n = int(byte_count)
        if n <= 0 or n % 2 != 0:
            raise ValueError("Bytes must be positive and even")
        if n > 4096:
            raise ValueError("Bytes exceeds maximum of 4096")
        if not self._streaming:
            return None
        with self._buffer_lock:
            if not self._buffer:
                return ""  # streaming but nothing buffered
            to_read = min(len(self._buffer), n)
            to_read -= to_read % 2  # PCM reads are truncated to an even count
            if to_read == 0:
                return ""
            chunk = bytes(self._buffer[:to_read])
            del self._buffer[:to_read]
        return chunk.decode("latin-1")

    def gain(self, val: int | None = None) -> int | None:
        if val is None:
            return self._gain
        self._gain = max(-10, min(10, int(val)))
        return None

    def stop(self) -> None:
        self._streaming = False
        with self._buffer_lock:
            self._buffer.clear()

    def status(self) -> str:
        # "le_audio" (LE Audio preemption) is not modelled in the emulator
        return "streaming" if self._streaming else "stopped"

    def aec(self, enable: bool | None = None) -> bool | None:
        if enable is None:
            return self._aec
        self._aec = bool(enable)
        return None

    def voice(self, enable: bool | None = None) -> bool | None:
        if enable is None:
            return self._voice
        self._voice = bool(enable)
        return None

    def diag(self, cmd: str) -> Any:
        cmd = str(cmd)
        if cmd == "stats":
            # Real firmware returns canceller/PDM/clock probe counters;
            # the emulator returns an empty table.
            return self._runtime.table() if self._runtime is not None else {}
        if cmd == "zero":
            return None
        raise ValueError(f"unknown diag command '{cmd}'")

    def aad_callback(
        self,
        func: Callable | None,
        threshold: int = 90,
        silent_period: int = 1000,
    ) -> None:
        self._aad_cb = func

    # ---- called from Python (test / host injection) ----

    def inject_data(self, data: bytes) -> None:
        """Queue capture bytes for the Lua script to read()."""
        with self._buffer_lock:
            self._buffer.extend(data)
