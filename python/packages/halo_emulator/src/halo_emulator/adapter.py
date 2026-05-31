"""
EmulatorBrilliantMsg — a BrilliantMsg-compatible async adapter for HaloEmulator.

Provides the same interface as ``brilliant_msg.BrilliantMsg`` so that host-side Python
scripts can switch between real Halo hardware and the emulator by changing a
single line:

    # Real hardware
    from brilliant_msg import BrilliantMsg
    frame = BrilliantMsg()

    # Emulator
    from halo_emulator import HaloEmulator, EmulatorBrilliantMsg
    frame = EmulatorBrilliantMsg(HaloEmulator())

The adapter bridges the async BrilliantMsg API to HaloEmulator's synchronous,
thread-based model:

- ``send_lua()`` calls ``execute_lua()`` directly (REPL mode, no running loop).
- ``send_message()`` frames the payload and calls ``inject_bluetooth_data()``.
- ``register_data_response_handler()`` installs a listener on the Bluetooth
  stub; when Lua calls ``frame.bluetooth.send()``, the listener dispatches the
  data to the matching handler (same msg_code routing as BrilliantMsg).
"""
from __future__ import annotations

import asyncio
import shutil
from pathlib import Path
from typing import Callable

from halo_emulator.emulator import HaloEmulator


class EmulatorBrilliantMsg:
    """
    BrilliantMsg-compatible adapter for HaloEmulator.

    Parameters
    ----------
    emulator:
        A ``HaloEmulator`` instance. The adapter adds a send-listener to the
        emulator's Bluetooth stub on construction; you should not add another
        listener independently.
    """

    def __init__(self, emulator: HaloEmulator) -> None:
        self._emu = emulator
        self._data_response_handlers: dict[int, list[tuple[object, Callable]]] = {}
        # Route Lua bluetooth.send() output back to Python handlers.
        # This listener is called from the Lua thread — handlers must be synchronous.
        self._emu._bluetooth.add_send_listener(self._on_lua_send)

    # ------------------------------------------------------------------ internal

    def _on_lua_send(self, data: bytes) -> None:
        """Called from the Lua thread whenever Lua calls frame.bluetooth.send()."""
        if not data:
            return
        msg_code = data[0]
        for _, handler in self._data_response_handlers.get(msg_code, []):
            handler(data)

    def _frame_message(self, msg_code: int, payload: bytes) -> bytes:
        """Build the framed packet that data.lua expects on its receive_callback."""
        total = len(payload)
        return bytes([msg_code, total >> 8, total & 0xFF]) + payload

    # ------------------------------------------------------------------ lifecycle

    async def connect(self, initialize: bool = True) -> bool:
        """
        Initialize the Lua runtime (REPL mode — no script is started).

        Call :meth:`upload_frame_app` + :meth:`start_frame_app` afterwards to
        run a full Lua app, or use :meth:`send_lua` for direct REPL commands.
        """
        self._emu.connect()
        return True

    async def disconnect(self) -> None:
        """Stop the emulator."""
        self._emu.stop()

    def is_connected(self) -> bool:
        return self._emu._lua is not None

    # ------------------------------------------------------------------ REPL mode

    async def send_lua(
        self,
        code: str,
        await_print: bool = False,
        show_me: bool = False,
    ) -> None:
        """
        Execute a Lua snippet directly.

        Only valid in REPL mode (after :meth:`connect`, before
        :meth:`start_frame_app`). Mirrors ``BrilliantMsg.send_lua()``.

        Note: ``await_print`` is accepted for API compatibility but has no
        effect — Lua ``print()`` output goes to the emulator's print_handler.
        """
        self._emu.execute_lua(code)

    async def print_short_text(self, text: str = "") -> None:
        """Display text before the main app starts (REPL mode convenience)."""
        sanitized = text.replace("'", "\\'").replace("\n", "")
        await self.send_lua(
            f"frame.display.text('{sanitized}', 1, 1, 0xFFFFFF); frame.display.show()"
        )

    # ------------------------------------------------------------------ app lifecycle

    async def upload_stdlua_libs(
        self,
        lib_names: list[str] | None = None,
        minified: bool = True,
    ) -> None:
        """
        Copy brilliant_msg standard Lua libraries into the emulator sandbox.

        These are the same files uploaded to real hardware (``data.min.lua``,
        ``plain_text.min.lua``, etc.).  Requires ``brilliant-msg`` to be installed.
        """
        if lib_names is None:
            lib_names = ["data"]
        try:
            from importlib.resources import files
            pkg = files("brilliant_msg")
        except ImportError as exc:
            raise ImportError(
                "upload_stdlua_libs() requires brilliant-msg to be installed: "
                "pip install brilliant-msg"
            ) from exc

        for lib in lib_names:
            suffix = ".min" if minified else ""
            content = pkg.joinpath(f"lua/{lib}{suffix}.lua").read_text(encoding="utf-8")
            dst = self._emu._sandbox_dir / f"{lib}{suffix}.lua"
            dst.write_text(content, encoding="utf-8")

    async def upload_frame_app(
        self,
        local_filename: str,
        frame_filename: str = "frame_app.lua",
    ) -> None:
        """Copy a Lua app file into the emulator sandbox."""
        shutil.copy2(local_filename, self._emu._sandbox_dir / frame_filename)

    async def start_frame_app(
        self,
        frame_app_name: str = "frame_app",
        await_print: bool = True,
    ) -> None:
        """
        Start the Lua app in the emulator.

        If ``await_print`` is True (default), waits 300 ms for the app to
        register its callbacks — equivalent to waiting for the first print()
        on real hardware.
        """
        self._emu.start(script_name=f"{frame_app_name}.lua")
        if await_print:
            await asyncio.sleep(0.3)

    async def stop_frame_app(self, reset: bool = True) -> None:
        """Stop the running Lua app."""
        self._emu.stop()

    # ------------------------------------------------------------------ message passing

    async def send_message(
        self,
        msg_code: int,
        payload: bytes,
        show_me: bool = False,
    ) -> None:
        """
        Send a structured message to the running Lua app.

        Frames the payload exactly as ``BrilliantBle.send_message()`` does, then
        injects it via ``inject_bluetooth_data()``.  The entire payload is sent
        as one packet (no MTU chunking) since the emulator has no BLE MTU limit.

        The Lua-side ``data.lua`` library will reassemble and parse it normally.
        """
        packet = self._frame_message(msg_code, payload)
        self._emu.inject_bluetooth_data(packet)
        # Yield briefly so the Lua thread can process the data and send its ACK
        await asyncio.sleep(0.05)

    def register_data_response_handler(
        self,
        subscriber: object,
        msg_codes: list[int],
        handler: Callable[[bytes], None],
    ) -> None:
        """
        Register a handler for Lua→host messages on specific msg codes.

        Mirrors ``BrilliantMsg.register_data_response_handler()``.  The handler
        receives the full raw bytes (first byte is the msg_code, same as on
        real hardware).

        The handler is called synchronously from the Lua thread — it must be a
        plain function, not a coroutine.
        """
        for code in msg_codes:
            self._data_response_handlers.setdefault(code, []).append((subscriber, handler))

    def unregister_data_response_handler(self, subscriber: object) -> None:
        """Unregister all handlers for a subscriber."""
        for code in list(self._data_response_handlers):
            self._data_response_handlers[code] = [
                (sub, h)
                for sub, h in self._data_response_handlers[code]
                if sub != subscriber
            ]

    # ------------------------------------------------------------------ print handler

    def attach_print_response_handler(self, handler: Callable = print) -> None:
        """Route Lua print() output to *handler*."""
        self._emu._print_handler = handler
        if self._emu._lua is not None:
            self._emu._lua.globals().print = handler

    def detach_print_response_handler(self) -> None:
        """Stop routing Lua print() output."""
        self._emu._print_handler = None

    # ------------------------------------------------------------------ emulator extras

    def get_framebuffer(self):
        """Return the current display as a 256×256 PIL Image."""
        return self._emu.get_framebuffer()

    def get_bluetooth_sent(self) -> list[bytes]:
        """Return all data the Lua app has sent via frame.bluetooth.send()."""
        return self._emu.get_bluetooth_sent()

    def inject_bluetooth_data(self, data: bytes) -> None:
        """Inject raw bytes into the Lua app's receive_callback (emulator only)."""
        self._emu.inject_bluetooth_data(data)

    def inject_button_single(self) -> None:
        self._emu.inject_button_single()

    def inject_button_double(self) -> None:
        self._emu.inject_button_double()

    def inject_button_long(self) -> None:
        self._emu.inject_button_long()

    def inject_imu_tap(self) -> None:
        self._emu.inject_imu_tap()
