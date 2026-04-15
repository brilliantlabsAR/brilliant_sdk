"""frame.speaker.* stubs — no-op for initial release."""
from __future__ import annotations

from typing import Any


class SpeakerStub:
    def __init__(self) -> None:
        self._volume: int = 50

    def start(self, cfg: Any = None) -> None:
        pass

    def play(self, data: Any) -> None:
        pass

    def volume(self, val: int | None = None) -> int | None:
        if val is None:
            return self._volume
        self._volume = max(0, min(100, int(val)))
        return None

    def stop(self) -> None:
        pass
