"""frame.button.* stubs."""
from __future__ import annotations

from typing import Callable


class ButtonStub:
    def __init__(self) -> None:
        self._single_cb: Callable | None = None
        self._double_cb: Callable | None = None
        self._long_cb: Callable | None = None

    # ---- called from Lua ----

    def single(self, func: Callable | None) -> None:
        self._single_cb = func

    def double(self, func: Callable | None) -> None:
        self._double_cb = func

    def long(self, func: Callable | None) -> None:
        self._long_cb = func

    # ---- called from event dispatch (Lua thread) ----

    def fire_single(self) -> None:
        if self._single_cb is not None:
            self._single_cb()

    def fire_double(self) -> None:
        if self._double_cb is not None:
            self._double_cb()

    def fire_long(self) -> None:
        if self._long_cb is not None:
            self._long_cb()
