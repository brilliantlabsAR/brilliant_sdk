"""frame.microphone.* stubs — no-op for initial release."""
from __future__ import annotations

from typing import Any, Callable


class MicrophoneStub:
    def __init__(self) -> None:
        self._gain: int = 0
        self._aad_cb: Callable | None = None

    def start(self, cfg: Any = None) -> None:
        pass

    def read(self, byte_count: int) -> str | None:
        return None  # No data in emulator

    def gain(self, val: int | None = None) -> int | None:
        if val is None:
            return self._gain
        self._gain = max(-10, min(10, int(val)))
        return None

    def stop(self) -> None:
        pass

    def aad_callback(
        self,
        func: Callable | None,
        threshold: int = 90,
        silent_period: int = 1000,
    ) -> None:
        self._aad_cb = func
