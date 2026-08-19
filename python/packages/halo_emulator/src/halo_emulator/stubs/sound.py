"""frame.sound.* stubs — sfxr sound-effect API surface (no audio output).

Mirrors firmware 0.8.8 lua_sound.c / sfxr.c: preset names, option defaults
and validation, blocking play vs play_async, and the (true) /
(nil, errstring, errcode) return convention.
"""
from __future__ import annotations

import threading
import time
from typing import Any

# Preset table from firmware sfxr.c
SOUND_PRESETS = ("pickup", "laser", "explosion", "powerup", "hit", "jump", "blip")

_ENOENT = -2


class SoundStub:
    def __init__(self, stop_event: threading.Event) -> None:
        self._stop_event = stop_event
        self._playing_until: float = 0.0

    @staticmethod
    def _read_options(opts: Any) -> tuple[int, int, int]:
        sample_rate, duration_ms, volume = 16000, 1000, 20
        if opts is not None:
            try:
                if opts.sample_rate is not None:
                    sample_rate = int(opts.sample_rate)
            except AttributeError:
                pass
            try:
                if opts.duration_ms is not None:
                    duration_ms = int(opts.duration_ms)
            except AttributeError:
                pass
            try:
                if opts.volume is not None:
                    volume = int(opts.volume)
            except AttributeError:
                pass
        if sample_rate not in (8000, 16000):
            raise ValueError("sample_rate must be 8000 or 16000")
        return sample_rate, duration_ms, volume

    def _start(self, name: str, opts: Any) -> tuple[None, str, int] | None:
        _rate, duration_ms, _volume = self._read_options(opts)
        if str(name) not in SOUND_PRESETS:
            return (None, "unknown sound preset", _ENOENT)
        self._playing_until = time.monotonic() + duration_ms / 1000.0
        return None  # success; duration already armed

    def play(self, name: str, opts: Any = None) -> object:
        """Blocking play: returns after the sound's duration has elapsed."""
        err = self._start(name, opts)
        if err is not None:
            return err
        # Block like the hardware does, but stay stoppable
        while time.monotonic() < self._playing_until:
            if self._stop_event.is_set():
                break
            time.sleep(0.005)
        return True

    def play_async(self, name: str, opts: Any = None) -> object:
        err = self._start(name, opts)
        if err is not None:
            return err
        return True

    def stop(self) -> None:
        self._playing_until = 0.0

    def is_playing(self) -> bool:
        return time.monotonic() < self._playing_until
