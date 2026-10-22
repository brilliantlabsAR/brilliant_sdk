"""frame.bluetooth.* stubs — captures sends, dispatches injected data."""
from __future__ import annotations

from typing import Callable


class BluetoothStub:
    def __init__(self) -> None:
        self._connected: bool = True
        self._address_str: str = "AA:BB:CC:DD:EE:FF"
        self._max_len: int = 243  # typical BLE MTU minus overhead
        self._receive_cb: Callable | None = None
        self._receive_buffer_size: int = 4096
        self._interval_ms: float = 30.0
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
        if not raw:
            return  # firmware: an empty string transmits nothing (still succeeds)
        self._sent.append(raw)
        for listener in self._send_listeners:
            listener(raw)

    def add_send_listener(self, listener: Callable[[bytes], None]) -> None:
        """Register a callback invoked (from the Lua thread) on every send."""
        self._send_listeners.append(listener)

    def receive_callback(self, func: Callable | None) -> None:
        """Called by Lua to register its incoming-data handler."""
        self._receive_cb = func

    def receive_buffer_size(self, size: object = None) -> int:
        """Get or set the data receive queue size (firmware range 1024-65536)."""
        if size is not None:
            size = int(size)
            if not 1024 <= size <= 65536:
                raise ValueError("size must be between 1024 and 65536 bytes")
            self._receive_buffer_size = size
        return self._receive_buffer_size

    def connection_interval(self, ms: object = None) -> float | None:
        """Get the connection interval, or request one (granted at once here)."""
        if ms is None:
            return self._interval_ms if self._connected else None
        ms = float(ms)
        if not 7.5 <= ms <= 1000:  # NaN fails too
            raise ValueError("interval must be between 7.5 and 1000 ms")
        if not self._connected:
            raise RuntimeError("not connected")
        self._interval_ms = ms
        return None

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
