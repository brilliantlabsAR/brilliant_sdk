"""
paired_sprite_ind_png.py — emulator port of brilliant_msg/examples/sprite_ind_png.py.

Displays three indexed-palette PNG images sequentially on the emulated display,
one at a time, to exercise 1-, 2-, and 4-bit-per-pixel sprite rendering:

  logo_1bit.png   —  1bpp, 2 colors
  street_2bit.png —  2bpp, 4 colors
  hotdog_4bit.png —  4bpp, 16 colors

All three use the standard Frame palette (the emulator default palette).

Usage:
    python paired_sprite_ind_png.py --emulator
    python paired_sprite_ind_png.py --emulator --record output.gif
    python paired_sprite_ind_png.py              # real Halo hardware

Requirements:
    pip install halo-emulator brilliant-msg
"""

import asyncio
import argparse
import os
import threading
from pathlib import Path

from brilliant_msg import TxSprite  # type: ignore[import]

SPRITE_MSG = 0x20

_FM_EXAMPLES = Path(__file__).parent / "../../brilliant_msg/examples"
LUA_APP = (_FM_EXAMPLES / "lua/sprite_frame_app.lua").resolve()
IMAGES = [
    (_FM_EXAMPLES / "images/logo_1bit.png").resolve(),
    (_FM_EXAMPLES / "images/street_2bit.png").resolve(),
    (_FM_EXAMPLES / "images/hotdog_4bit.png").resolve(),
]


def _run_pygame_window(emulator: object) -> None:
    os.environ.setdefault("SDL_VIDEO_WINDOW_POS", "100,100")
    import pygame
    pygame.display.init()
    scale = 2
    screen = pygame.display.set_mode((256 * scale, 256 * scale))
    pygame.display.set_caption("Halo Emulator — sprite ind png")
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
    parser = argparse.ArgumentParser(description="Indexed PNG sprite display demo")
    parser.add_argument("--emulator", action="store_true", help="Use the emulator")
    parser.add_argument("--record", default=None, metavar="OUTPUT",
                        help="Record to a file (.gif or .mp4 with imageio[ffmpeg])")
    parser.add_argument("--fps", type=float, default=30.0, metavar="N",
                        help="Recording frame rate (default: 30)")
    args = parser.parse_args()

    emu = None

    if args.emulator:
        from halo_emulator import HaloEmulator, EmulatorBrilliantMsg
        emu = HaloEmulator()
        frame = EmulatorBrilliantMsg(emu)
    else:
        from brilliant_msg import BrilliantMsg  # type: ignore[import]
        frame = BrilliantMsg()

    try:
        await frame.connect()

        await frame.upload_stdlua_libs(lib_names=["data", "sprite"])
        await frame.upload_frame_app(
            local_filename=str(LUA_APP),
            frame_filename="sprite_frame_app.lua",
        )

        frame.attach_print_response_handler()
        await frame.start_frame_app(frame_app_name="sprite_frame_app", await_print=True)

        if args.emulator:
            threading.Thread(
                target=_run_pygame_window, args=(emu,), daemon=True, name="pygame-window"
            ).start()

        if args.emulator and args.record:
            emu.start_recording(fps=args.fps)
            print(f"Recording at {args.fps:.0f} fps → {args.record}")

        for image_path in IMAGES:
            sprite = TxSprite.from_indexed_png_bytes(image_path.read_bytes())
            print(f"Sending {image_path.name}: {sprite.width}×{sprite.height}, "
                  f"{sprite.num_colors} colors, {sprite.bpp}bpp")
            await frame.send_message(SPRITE_MSG, sprite.pack())
            await asyncio.sleep(3.0)   # display each image for 3 seconds

        frame.detach_print_response_handler()

    finally:
        if args.emulator and args.record:
            emu.stop_recording(args.record)
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
