"""frame.bluetooth.* stubs — captures sends, dispatches injected data."""
from __future__ import annotations

from typing import Callable


class BluetoothStub:
    def __init__(self) -> None:
        self._connected: bool = True
        self._address_str: str = "AA:BB:CC:DD:EE:FF"
        self._max_len: int = 243  # typical BLE MTU minus overhead
        self._receive_cb: Callable | None = None
        self._sent: list[bytes] = []
        self._send_listeners: list[Callable[[bytes], None]] = []

    # ---- called from Lua ----

    def is_connected(self) -> bool:
        return self._connected

    def address(self) -> str:
        return self._address_str

    def max_length(self) -> int:
        return self._max_len

    def send(self, data: object) -> None:
        """Called by Lua to send data to the host. Captured for test inspection."""
        if isinstance(data, (bytes, bytearray)):
            raw = bytes(data)
        else:
            raw = str(data).encode("latin-1")
        self._sent.append(raw)
        for listener in self._send_listeners:
            listener(raw)

    def add_send_listener(self, listener: Callable[[bytes], None]) -> None:
        """Register a callback invoked (from the Lua thread) on every send."""
        self._send_listeners.append(listener)

    def receive_callback(self, func: Callable | None) -> None:
        """Called by Lua to register its incoming-data handler."""
        self._receive_cb = func

    # ---- called from Python (event dispatch) ----

    def dispatch(self, data: bytes) -> None:
        """Deliver bytes to the Lua receive_callback (called from Lua thread only)."""
        if self._receive_cb is not None:
            # Pass as a latin-1 string so Lua sees it as a byte string
            lua_str = data.decode("latin-1")
            self._receive_cb(lua_str)

    # ---- test observation API ----

    def get_sent(self) -> list[bytes]:
        return list(self._sent)

    def clear_sent(self) -> None:
        self._sent.clear()
