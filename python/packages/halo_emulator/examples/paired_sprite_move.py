"""
paired_sprite_move.py — emulator port of brilliant_msg/examples/sprite_move.py.

Sends a 1-bit indexed PNG sprite to the Lua app once, then moves it to 10
random positions on the 256×256 display, pausing 1 second at each position.

Message protocol:
  0x20  TxSprite       — upload the sprite (palette + pixel data)
  0x40  TxSpriteCoords — place sprite 0x20 at (x, y) with palette offset
  0x50  TxCode         — signal the Lua app to show the current frame

Usage:
    python paired_sprite_move.py --emulator
    python paired_sprite_move.py --emulator --record output.gif
    python paired_sprite_move.py              # real Halo hardware

Requirements:
    pip install halo-emulator brilliant-msg
"""

import asyncio
import argparse
import os
import threading
from pathlib import Path
from random import randint

from brilliant_msg import TxSprite, TxSpriteCoords, TxCode  # type: ignore[import]

SPRITE_MSG  = 0x20
COORDS_MSG  = 0x40
DRAW_MSG    = 0x50

_FM_EXAMPLES = Path(__file__).parent / "../../brilliant_msg/examples"
LUA_APP  = (_FM_EXAMPLES / "lua/sprite_game_app.lua").resolve()
IMAGE    = (_FM_EXAMPLES / "images/rings_1bit.png").resolve()

LUA_LIBS = ["data", "sprite", "code", "sprite_coords"]


def _run_pygame_window(emulator: object) -> None:
    os.environ.setdefault("SDL_VIDEO_WINDOW_POS", "100,100")
    import pygame
    pygame.display.init()
    scale = 2
    screen = pygame.display.set_mode((256 * scale, 256 * scale))
    pygame.display.set_caption("Halo Emulator — sprite move")
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
    parser = argparse.ArgumentParser(description="Sprite move demo")
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

        await frame.upload_stdlua_libs(lib_names=LUA_LIBS)
        await frame.upload_frame_app(
            local_filename=str(LUA_APP),
            frame_filename="sprite_game_app.lua",
        )

        frame.attach_print_response_handler()
        await frame.start_frame_app(frame_app_name="sprite_game_app", await_print=True)

        if args.emulator:
            threading.Thread(
                target=_run_pygame_window, args=(emu,), daemon=True, name="pygame-window"
            ).start()

        if args.emulator and args.record:
            emu.start_recording(fps=args.fps)
            print(f"Recording at {args.fps:.0f} fps → {args.record}")

        # Upload the sprite once
        sprite = TxSprite.from_indexed_png_bytes(IMAGE.read_bytes())
        print(f"Sending sprite: {sprite.width}×{sprite.height}, {sprite.num_colors} colors, {sprite.bpp}bpp")
        await frame.send_message(SPRITE_MSG, sprite.pack())
        await asyncio.sleep(0.2)   # let Lua parse and store the sprite

        # Move to 10 random positions
        for i in range(10):
            x = randint(1, 256 - sprite.width)
            y = randint(1, 256 - sprite.height)
            print(f"  Position {i+1:2d}: ({x}, {y})")
            await frame.send_message(COORDS_MSG, TxSpriteCoords(SPRITE_MSG, x, y, 0).pack())
            await frame.send_message(DRAW_MSG, TxCode(0).pack())
            await asyncio.sleep(1.0)

        frame.detach_print_response_handler()

    finally:
        if args.emulator and args.record:
            emu.stop_recording(args.record)
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
