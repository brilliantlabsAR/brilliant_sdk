"""Display frame recorder — captures the emulator framebuffer to a video file."""
from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
from PIL import Image

if TYPE_CHECKING:
    from halo_emulator.emulator import HaloEmulator


class VideoRecorder:
    """
    Captures frames from a :class:`HaloEmulator` display and writes a video file.

    Supported output formats:

    - ``.gif`` — animated GIF via Pillow (no extra dependencies)
    - ``.mp4``, ``.webm``, ``.avi``, etc. — via ``imageio[ffmpeg]``
      (``pip install 'imageio[ffmpeg]'`` or ``pip install 'halo-emulator[video]'``)

    Example::

        recorder = VideoRecorder(emulator, fps=30)
        recorder.start()
        # ... run app ...
        recorder.stop("output.mp4")
    """

    def __init__(self, emulator: "HaloEmulator", fps: float = 30.0) -> None:
        self._emu = emulator
        self._fps = float(fps)
        self._frames: list[Image.Image] = []
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

    @property
    def frame_count(self) -> int:
        return len(self._frames)

    def start(self) -> None:
        """Start capturing frames in a background thread."""
        self._stop_event.clear()
        self._frames = []
        self._thread = threading.Thread(
            target=self._capture_loop, daemon=True, name="halo-recorder"
        )
        self._thread.start()

    def _capture_loop(self) -> None:
        interval = 1.0 / self._fps
        next_time = time.monotonic() + interval
        while not self._stop_event.is_set():
            self._frames.append(self._emu.get_framebuffer())
            sleep_time = next_time - time.monotonic()
            if sleep_time > 0:
                time.sleep(sleep_time)
            next_time += interval

    def stop(self, output_path: str | Path) -> None:
        """Stop capture and save to *output_path*."""
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=2.0)
        if not self._frames:
            print("[halo-emulator] No frames captured; video not written.")
            return
        self._save(Path(output_path))

    def _save(self, path: Path) -> None:
        if path.suffix.lower() == ".gif":
            self._save_gif(path)
        else:
            self._save_video(path)

    def _save_gif(self, path: Path) -> None:
        frames_rgb = [f.convert("RGB") for f in self._frames]
        duration_ms = int(1000 / self._fps)
        frames_rgb[0].save(
            path,
            save_all=True,
            append_images=frames_rgb[1:],
            loop=0,
            duration=duration_ms,
            optimize=False,
        )
        print(f"[halo-emulator] Recorded {len(self._frames)} frames → {path}")

    def _save_video(self, path: Path) -> None:
        try:
            import imageio  # type: ignore[import]
        except ImportError:
            raise ImportError(
                f"Writing {path.suffix!r} requires imageio: "
                "pip install 'imageio[ffmpeg]'  "
                "or  pip install 'halo-emulator[video]'"
            ) from None
        with imageio.get_writer(str(path), fps=self._fps) as writer:
            for frame in self._frames:
                writer.append_data(np.array(frame.convert("RGB")))
        print(f"[halo-emulator] Recorded {len(self._frames)} frames → {path}")
