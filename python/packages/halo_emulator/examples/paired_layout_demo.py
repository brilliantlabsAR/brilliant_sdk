"""
paired_layout_demo.py — host-side companion for the simple_brilliant_app layout example.

Loads the Halo layout Lua app, switches to SpeechLayout, then:
  - Sends REC_MSG=1        (recording indicator on)
  - Sends SPEECH_WAVE_MSG=1  (speech wave animation on)
  - Waits 10 seconds
  - Sends REC_MSG=0        (recording indicator off)
  - Sends SPEECH_WAVE_MSG=0  (speech wave animation off)

Usage:
    python paired_layout_demo.py --emulator   # emulator, opens pygame window
    python paired_layout_demo.py              # real Halo hardware

Requirements:
    pip install halo-emulator brilliant-msg
"""

import asyncio
import argparse
import os
import threading
from pathlib import Path

REC_MSG         = 0x40   # value: 1 = recording, 0 = not recording
SPEECH_WAVE_MSG = 0x70   # value: 1 = active,    0 = inactive
SET_LAYOUT_MSG  = 0x60   # value: 1 = TextLayout, 2 = SpeechLayout, 3 = EncounterLayout

_BASE = Path(__file__).parent / "../../../../flutter/packages"

# Lua libraries from the Flutter frame_msg package (newer data.min.lua API)
FLUTTER_LUA_LIBS = (_BASE / "frame_msg/lib/lua").resolve()

# Layout app assets (frame_app.lua + minified layout/view modules)
LAYOUT_ASSETS = (
    _BASE / "simple_brilliant_app/examples/layout/assets"
).resolve()


def _run_pygame_window(emulator: object) -> None:
    """Display the emulator framebuffer in a pygame window (runs in a thread)."""
    os.environ.setdefault("SDL_VIDEO_WINDOW_POS", "100,100")
    import pygame
    pygame.display.init()
    scale = 2
    screen = pygame.display.set_mode((256 * scale, 256 * scale))
    pygame.display.set_caption("Halo Emulator")
    clock = pygame.time.Clock()
    while True:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return
        img = emulator.get_framebuffer()  # type: ignore[union-attr]
        surface = pygame.image.fromstring(img.tobytes(), (256, 256), img.mode)
        screen.blit(pygame.transform.scale(surface, (256 * scale, 256 * scale)), (0, 0))
        pygame.display.flip()
        clock.tick(30)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Halo layout app demo")
    parser.add_argument("--emulator", action="store_true", help="Use the emulator")
    parser.add_argument("--record", default=None, metavar="OUTPUT",
                        help="Record display to a file (.gif or .mp4/.webm with imageio[ffmpeg])")
    parser.add_argument("--fps", type=float, default=30.0, metavar="N",
                        help="Recording frame rate (default: 30)")
    args = parser.parse_args()

    emu = None

    if args.emulator:
        from halo_emulator import HaloEmulator, EmulatorBrilliantMsg

        emu = HaloEmulator()

        # Load standard Lua libs from the Flutter frame_msg package.
        # These have a newer data.min.lua API (process_raw_items returns an
        # ordered array of {flag, raw} pairs) that frame_app.lua depends on.
        for name in ["data", "code", "battery", "text_sprite_block", "image_sprite_block"]:
            emu.load_file(FLUTTER_LUA_LIBS / f"{name}.min.lua")

        # Load all minified layout/view Lua modules into the sandbox.
        # rglob picks up both lua/min/layout/*.min.lua and lua/min/view/*.min.lua.
        for f in (LAYOUT_ASSETS / "lua/min").rglob("*.lua"):
            emu.load_file(f)

        frame = EmulatorBrilliantMsg(emu)
    else:
        from brilliant_msg import BrilliantMsg          # type: ignore[import]
        frame = BrilliantMsg()

    try:
        await frame.connect()

        await frame.upload_frame_app(
            local_filename=str(LAYOUT_ASSETS / "frame_app.lua"),
            frame_filename="frame_app.lua",
        )
        await frame.start_frame_app(frame_app_name="frame_app", await_print=True)

        if args.emulator and args.record:
            emu.start_recording(fps=args.fps)
            print(f"Recording at {args.fps:.0f} fps → {args.record}")

        if args.emulator:
            win_thread = threading.Thread(
                target=_run_pygame_window, args=(emu,), daemon=True, name="pygame-window"
            )
            win_thread.start()

        # Switch to SpeechLayout before sending speech wave messages
        print("Switching to SpeechLayout")
        await frame.send_message(SET_LAYOUT_MSG, bytes([2]))
        await asyncio.sleep(0.1)   # let the layout switch render

        print("Sending REC_MSG=1, SPEECH_WAVE_MSG=1")
        await frame.send_message(REC_MSG, bytes([1]))
        await frame.send_message(SPEECH_WAVE_MSG, bytes([1]))

        print("Waiting 10 seconds ...")
        await asyncio.sleep(10)

        print("Sending REC_MSG=0, SPEECH_WAVE_MSG=0")
        await frame.send_message(REC_MSG, bytes([0]))
        await frame.send_message(SPEECH_WAVE_MSG, bytes([0]))

        await asyncio.sleep(1)

    finally:
        if args.emulator and args.record:
            emu.stop_recording(args.record)
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
