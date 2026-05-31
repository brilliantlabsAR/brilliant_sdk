"""
paired_text_sprite_block.py — emulator port of brilliant_msg/examples/text_sprite_block.py.

Rasterizes text on the host using TrueType/OpenType fonts and sends the resulting
bitmap sprites to the Lua app for display. Demonstrates multi-script text rendering
including CJK, Hebrew (right-to-left), and Arabic (right-to-left).

Message protocol:
  0x20  TxTextSpriteBlock  — header (once) then one sprite slice per text line
  0x21  TxCode             — clear the display and reset the text block

Usage:
    python paired_text_sprite_block.py --emulator
    python paired_text_sprite_block.py --emulator --record output.gif
    python paired_text_sprite_block.py              # real Halo hardware

Requirements:
    pip install halo-emulator brilliant-msg
"""

import asyncio
import argparse
import os
import threading
from pathlib import Path

from brilliant_msg import TxTextSpriteBlock, TxCode  # type: ignore[import]

TEXT_SPRITE_BLOCK_MSG = 0x20
RESET_MSG             = 0x21

_FM_EXAMPLES = Path(__file__).parent / "../../brilliant_msg/examples"
LUA_APP  = (_FM_EXAMPLES / "lua/text_sprite_block_frame_app.lua").resolve()
FONTS    = (_FM_EXAMPLES / "fonts").resolve()


def _run_pygame_window(emulator: object) -> None:
    os.environ.setdefault("SDL_VIDEO_WINDOW_POS", "100,100")
    import pygame
    pygame.display.init()
    scale = 2
    screen = pygame.display.set_mode((256 * scale, 256 * scale))
    pygame.display.set_caption("Halo Emulator — text sprite block")
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


async def send_text(frame, text: str, tsb: TxTextSpriteBlock) -> None:
    """Rasterize *text* with *tsb* and stream header + sprite slices to the app."""
    sprites = tsb.create_text_sprites(text)
    await frame.send_message(TEXT_SPRITE_BLOCK_MSG, tsb.pack())
    for spr in sprites:
        await frame.send_message(TEXT_SPRITE_BLOCK_MSG, spr.pack())
        await asyncio.sleep(0.1)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Text sprite block demo")
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

        await frame.upload_stdlua_libs(lib_names=["data", "code", "text_sprite_block"])
        await frame.upload_frame_app(
            local_filename=str(LUA_APP),
            frame_filename="text_sprite_block_frame_app.lua",
        )

        frame.attach_print_response_handler()
        await frame.start_frame_app(
            frame_app_name="text_sprite_block_frame_app", await_print=True
        )

        if args.emulator:
            threading.Thread(
                target=_run_pygame_window, args=(emu,), daemon=True, name="pygame-window"
            ).start()

        if args.emulator and args.record:
            emu.start_recording(fps=args.fps)
            print(f"Recording at {args.fps:.0f} fps → {args.record}")

        # --- multi-script text with CJK font ---
        print("Sending multi-script text (Latin, CJK, Cyrillic, Korean)...")
        tsb = TxTextSpriteBlock(
            width=256,
            line_height=30,
            font_size=20,
            max_display_lines=5,
            font_family=str(FONTS / "NotoSansCJK-VF.ttf.ttc"),
        )
        await send_text(
            frame,
            "Hello, friend!\nこんにちは、友人！\n朋友你好！\nПривет, друг!\n안녕, 친구!",
            tsb,
        )
        await asyncio.sleep(5.0)

        # --- Hebrew (right-to-left) ---
        print("Sending Hebrew text...")
        await frame.send_message(RESET_MSG, TxCode().pack())
        await asyncio.sleep(0.2)

        tsb = TxTextSpriteBlock(
            width=256,
            line_height=30,
            font_size=20,
            max_display_lines=1,
            font_family=str(FONTS / "NotoSansHebrew-Regular.ttf"),
        )
        await send_text(frame, "שלום, חבר!", tsb)
        await asyncio.sleep(3.0)

        # --- Arabic (right-to-left) ---
        print("Sending Arabic text...")
        await frame.send_message(RESET_MSG, TxCode().pack())
        await asyncio.sleep(0.2)

        tsb = TxTextSpriteBlock(
            width=256,
            line_height=30,
            font_size=18,
            max_display_lines=1,
            font_family=str(FONTS / "NotoKufiArabic-Regular.ttf"),
        )
        await send_text(frame, "مرحبا يا صديق", tsb)
        await asyncio.sleep(3.0)

        await frame.send_message(RESET_MSG, TxCode().pack())
        frame.detach_print_response_handler()

    finally:
        if args.emulator and args.record:
            emu.stop_recording(args.record)
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
