"""HaloEmulator — main public class."""
from __future__ import annotations

import shutil
import tempfile
import threading
from pathlib import Path
from typing import Callable

from PIL import Image

from halo_emulator.display import DisplayBuffer
from halo_emulator.event_queue import Event, EventQueue
from halo_emulator.stubs.bluetooth import BluetoothStub
from halo_emulator.stubs.button import ButtonStub
from halo_emulator.stubs.compression import CompressionStub
from halo_emulator.stubs.file_stubs import FileStub
from halo_emulator.stubs.imu import ImuStub
from halo_emulator.stubs.microphone import MicrophoneStub
from halo_emulator.stubs.speaker import SpeakerStub
from halo_emulator.stubs.system import EmulatorStopException, SystemStub
from halo_emulator.stubs.time_stubs import TimeStub


class HaloEmulator:
    """
    Halo device emulator.

    Runs a user Lua 5.3 script in an embedded VM (via lupa) with all
    ``frame.*`` API calls stubbed out. Python can inject events and
    inspect outputs for testing or interactive development.

    Example::

        emu = HaloEmulator(sandbox_dir='./my_app')
        emu.load_directory('./my_app')
        emu.start('main.lua')
        emu.inject_button_single()
        img = emu.get_framebuffer()
        emu.stop()
    """

    def __init__(
        self,
        sandbox_dir: str | Path | None = None,
        *,
        print_handler: Callable[[str], None] | None = print,
    ) -> None:
        """
        Parameters
        ----------
        sandbox_dir:
            Directory used as the Lua filesystem root. If *None* a temporary
            directory is created automatically.
        print_handler:
            Called with each Lua ``print()`` output line. Defaults to
            ``print``. Pass ``None`` to suppress output.
        """
        if sandbox_dir is None:
            self._sandbox_dir = Path(tempfile.mkdtemp(prefix="halo_emu_"))
            self._owns_sandbox = True
        else:
            self._sandbox_dir = Path(sandbox_dir).resolve()
            self._sandbox_dir.mkdir(parents=True, exist_ok=True)
            self._owns_sandbox = False

        self._print_handler = print_handler

        # Internal state
        self._stop_event = threading.Event()
        self._event_queue = EventQueue()
        self._display = DisplayBuffer()
        self._bluetooth = BluetoothStub()
        self._button = ButtonStub()
        self._imu = ImuStub(runtime=None)  # runtime set in lua_runtime.py
        self._time = TimeStub(runtime=None)
        self._file = FileStub(self._sandbox_dir)
        self._compression = CompressionStub()
        self._speaker = SpeakerStub()
        self._microphone = MicrophoneStub()
        self._system = SystemStub(
            event_queue=self._event_queue,
            dispatch_fn=self._dispatch_event,
            stop_event=self._stop_event,
        )

        self._lua = None
        self._lua_thread: threading.Thread | None = None
        self._lua_error: Exception | None = None
        self._running = False
        self._recorder = None  # VideoRecorder | None

    # ------------------------------------------------------------------ lifecycle

    def load_file(self, lua_file: str | Path) -> None:
        """Copy a single Lua file into the sandbox directory."""
        src = Path(lua_file)
        shutil.copy2(src, self._sandbox_dir / src.name)

    def load_directory(self, lua_dir: str | Path) -> None:
        """Copy all ``.lua`` files from *lua_dir* into the sandbox directory."""
        for f in Path(lua_dir).glob("*.lua"):
            dst = self._sandbox_dir / f.name
            if f.resolve() != dst.resolve():
                shutil.copy2(f, dst)

    def _build_runtime(self) -> None:
        from halo_emulator.lua_runtime import build_lua_runtime
        self._lua = build_lua_runtime(
            display=self._display,
            bluetooth=self._bluetooth,
            button=self._button,
            imu=self._imu,
            system=self._system,
            time_stub=self._time,
            file_stub=self._file,
            compression=self._compression,
            speaker=self._speaker,
            microphone=self._microphone,
            sandbox_dir=self._sandbox_dir,
        )
        if self._print_handler is not None:
            self._lua.globals().print = self._print_handler

    def connect(self) -> None:
        """
        Initialize the Lua runtime without starting a script thread.

        Use this for REPL-style operation where Lua snippets are executed
        directly via :meth:`execute_lua`. Safe to call multiple times.
        """
        self._stop_event.clear()
        self._lua_error = None
        self._build_runtime()

    def execute_lua(self, code: str) -> object:
        """
        Execute a Lua snippet directly in the current runtime.

        Only safe when no main-loop thread is running (i.e. after
        :meth:`connect` but before :meth:`start`, or after :meth:`stop`).
        """
        if self._lua is None:
            raise RuntimeError("Lua runtime not initialized — call connect() first.")
        if self._running:
            raise RuntimeError("Cannot execute_lua() while a script thread is running.")
        return self._lua.execute(code)

    def start(self, script_name: str = "main.lua") -> None:
        """
        Build the Lua runtime and run *script_name* in a background thread.

        Returns immediately; use :meth:`wait` to block until the script exits.
        """
        self._stop_event.clear()
        self._lua_error = None
        self._build_runtime()

        self._running = True
        self._lua_thread = threading.Thread(
            target=self._run_lua,
            args=(script_name,),
            daemon=True,
            name="halo-lua-vm",
        )
        self._lua_thread.start()

    def _run_lua(self, script_name: str) -> None:
        try:
            script_path = self._sandbox_dir / script_name
            code = script_path.read_text(encoding="utf-8")
            self._lua.execute(code)
        except EmulatorStopException:
            pass  # clean stop
        except Exception as exc:
            self._lua_error = exc
            if self._print_handler is not None:
                self._print_handler(f"[halo-emulator] Lua error: {exc}")
        finally:
            self._running = False

    def stop(self) -> None:
        """Signal the Lua VM to stop and wait up to 2 s for the thread."""
        self._stop_event.set()
        self._event_queue.put(Event(type="stop"))
        if self._lua_thread is not None:
            self._lua_thread.join(timeout=2.0)

    def wait(self, timeout: float | None = None) -> None:
        """Block until the Lua script exits (or raises its exception)."""
        if self._lua_thread is not None:
            self._lua_thread.join(timeout=timeout)
        if self._lua_error is not None:
            raise self._lua_error

    def is_running(self) -> bool:
        return self._running

    def get_error(self) -> Exception | None:
        return self._lua_error

    # ------------------------------------------------------------------ event dispatch (Lua thread)

    def _dispatch_event(self, event: Event) -> None:
        if event.type == "ble":
            self._bluetooth.dispatch(event.data)
        elif event.type == "button_single":
            self._button.fire_single()
        elif event.type == "button_double":
            self._button.fire_double()
        elif event.type == "button_long":
            self._button.fire_long()
        elif event.type == "imu_tap":
            self._imu.fire_tap()

    # ------------------------------------------------------------------ injection API

    def inject_bluetooth_data(self, data: bytes) -> None:
        """Simulate data arriving from the host — triggers the Lua receive_callback."""
        self._event_queue.put(Event(type="ble", data=bytes(data)))

    def inject_button_single(self) -> None:
        self._event_queue.put(Event(type="button_single"))

    def inject_button_double(self) -> None:
        self._event_queue.put(Event(type="button_double"))

    def inject_button_long(self) -> None:
        self._event_queue.put(Event(type="button_long"))

    def inject_imu_tap(self) -> None:
        self._event_queue.put(Event(type="imu_tap"))

    # ------------------------------------------------------------------ configuration API

    def set_battery_level(self, level: int) -> None:
        self._system._battery_level = int(level)

    def set_battery_charging(self, charging: bool) -> None:
        self._system._battery_charging = bool(charging)

    def set_imu_direction(self, pitch: float, roll: float, heading: float) -> None:
        self._imu.set_direction(pitch, roll, heading)

    def set_imu_raw(
        self,
        compass: tuple[float, float, float],
        accel: tuple[float, float, float],
    ) -> None:
        self._imu.set_raw(compass, accel)

    # ------------------------------------------------------------------ observation API

    def get_framebuffer(self) -> Image.Image:
        """Return a 256×256 PIL RGBA Image of the current display contents."""
        return self._display.get_image()

    def get_bluetooth_sent(self) -> list[bytes]:
        """Return all byte payloads the Lua script sent via ``frame.bluetooth.send()``."""
        return self._bluetooth.get_sent()

    def clear_bluetooth_sent(self) -> None:
        self._bluetooth.clear_sent()

    # ------------------------------------------------------------------ recording

    def start_recording(self, fps: float = 30.0) -> None:
        """Start capturing display frames for video output.

        Call :meth:`stop_recording` with an output path to save the result.
        Supported formats: ``.gif`` (Pillow) and ``.mp4`` / ``.webm`` / ``.avi``
        (requires ``pip install 'imageio[ffmpeg]'``).
        """
        from halo_emulator.recorder import VideoRecorder
        self._recorder = VideoRecorder(self, fps=fps)
        self._recorder.start()

    def stop_recording(self, output_path: str | Path) -> None:
        """Stop frame capture and write the video to *output_path*."""
        if self._recorder is None:
            return
        self._recorder.stop(output_path)
        self._recorder = None

    # ------------------------------------------------------------------ cleanup

    def __enter__(self) -> "HaloEmulator":
        return self

    def __exit__(self, *_: object) -> None:
        if self._running:
            self.stop()
        if self._owns_sandbox:
            shutil.rmtree(self._sandbox_dir, ignore_errors=True)
