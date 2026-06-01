"""halo-emulator CLI entry point."""
from __future__ import annotations

import argparse
import code
import os
import threading
from pathlib import Path


def _pygame_window(emulator: object, stop_event: threading.Event) -> None:  # type: ignore[type-arg]
    """Run a pygame window showing the emulator display.

    On macOS this must run on the main thread: SDL's Cocoa backend sets the
    application main menu during video init, which AppKit only permits from the
    main thread. The loop exits when the window is closed or ``stop_event`` is
    set (e.g. when the REPL exits).
    """
    os.environ.setdefault("SDL_VIDEO_WINDOW_POS", "100,100")
    import pygame

    pygame.display.init()
    scale = 2
    screen = pygame.display.set_mode((256 * scale, 256 * scale))
    pygame.display.set_caption("Halo Emulator")
    clock = pygame.time.Clock()

    key_map = {
        pygame.K_SPACE: "inject_button_single",
        pygame.K_d: "inject_button_double",
        pygame.K_l: "inject_button_long",
        pygame.K_t: "inject_imu_tap",
    }

    while not stop_event.is_set():
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                stop_event.set()
                break
            elif event.type == pygame.KEYDOWN:
                method = key_map.get(event.key)
                if method:
                    getattr(emulator, method)()

        img = emulator.get_framebuffer()  # type: ignore[union-attr]
        mode = img.mode
        raw = img.tobytes()
        surface = pygame.image.fromstring(raw, (256, 256), mode)
        scaled = pygame.transform.scale(surface, (256 * scale, 256 * scale))
        screen.blit(scaled, (0, 0))
        pygame.display.flip()
        clock.tick(30)

    pygame.display.quit()


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="halo-emulator",
        description="Halo smart glasses Lua emulator",
    )
    parser.add_argument(
        "app_dir",
        nargs="?",
        default=None,
        help="Directory containing Lua app files (loaded into sandbox)",
    )
    parser.add_argument(
        "--script",
        default="main.lua",
        metavar="NAME",
        help="Entry-point Lua filename (default: main.lua)",
    )
    parser.add_argument(
        "--sandbox",
        default=None,
        metavar="DIR",
        help="Explicit sandbox directory (default: app_dir or temp dir)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Skip the pygame display window",
    )
    parser.add_argument(
        "--record",
        default=None,
        metavar="OUTPUT",
        help=(
            "Record the display to a video file. "
            "Use .gif for animated GIF (no extra deps) or "
            ".mp4/.webm/.avi for video (requires imageio[ffmpeg])."
        ),
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=30.0,
        metavar="N",
        help="Recording frame rate (default: 30)",
    )
    args = parser.parse_args()

    from halo_emulator import HaloEmulator

    sandbox = args.sandbox or args.app_dir
    emulator = HaloEmulator(sandbox_dir=sandbox)

    if args.app_dir:
        emulator.load_directory(args.app_dir)
        emulator.start(script_name=args.script)

    if args.record:
        emulator.start_recording(fps=args.fps)
        print(f"[halo-emulator] Recording at {args.fps:.0f} fps → {args.record}")

    banner = (
        "Halo Emulator — 'emulator' is in scope\n"
        "Keyboard (window): SPACE=single click, D=double, L=long, T=tap\n"
        "Python API:\n"
        "  emulator.inject_bluetooth_data(b'...')\n"
        "  emulator.inject_button_single()\n"
        "  emulator.inject_imu_tap()\n"
        "  emulator.get_framebuffer().save('frame.png')\n"
        "  emulator.get_bluetooth_sent()\n"
        "  emulator.start_recording(fps=30) / emulator.stop_recording('out.mp4')\n"
    )

    if args.headless:
        code.interact(local={"emulator": emulator}, banner=banner)
    else:
        # The pygame window must own the main thread (macOS Cocoa requires GUI
        # init on the main thread), so the REPL runs on a background thread.
        stop_event = threading.Event()

        def _run_repl() -> None:
            try:
                code.interact(local={"emulator": emulator}, banner=banner)
            finally:
                stop_event.set()

        repl_thread = threading.Thread(target=_run_repl, daemon=True, name="repl")
        repl_thread.start()
        try:
            _pygame_window(emulator, stop_event)
        except KeyboardInterrupt:
            stop_event.set()

    emulator.stop()

    if args.record:
        emulator.stop_recording(args.record)
