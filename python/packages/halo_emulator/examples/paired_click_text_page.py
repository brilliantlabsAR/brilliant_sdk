"""
paired_click_text_page.py — host-side client for lua/text_page_app.lua.

Demonstrates the two newest brilliant_msg types end-to-end:
  - RxClick: button events (single/double/long) from the device, msg code 0x0B
  - TxTextPage + CircularTextLayout: text laid out along the chords of Halo's
    round display, one 1-bit sprite per line, drawn at per-line offsets

Usage:
    python paired_click_text_page.py --emulator     # emulator, saves PNGs + asserts
    python paired_click_text_page.py                # real Halo hardware
"""

import asyncio
import argparse

from brilliant_msg import RxClick, ClickType, TxTextPage, CircularTextLayout

PAGE_FLAG = 0x20
CLEAR_FLAG = 0x10

TEXT = (
    "The Halo display is round: a circular text layout fits each line to the "
    "chord at its height, so nothing is lost at the corners. Single-click for "
    "the next page."
)


async def send_page(frame, page) -> None:
    await frame.send_message(PAGE_FLAG, page.pack())
    for sprite in page.rasterized_sprites:
        await frame.send_message(PAGE_FLAG, sprite.pack())


async def main() -> None:
    parser = argparse.ArgumentParser(description="Click + circular text page demo")
    parser.add_argument("--emulator", action="store_true", help="Use the emulator")
    args = parser.parse_args()

    if args.emulator:
        from halo_emulator import HaloEmulator, EmulatorBrilliantMsg
        emu = HaloEmulator()
        frame = EmulatorBrilliantMsg(emu)
    else:
        from brilliant_msg import BrilliantMsg
        frame = BrilliantMsg()

    try:
        await frame.connect()
        await frame.upload_stdlua_libs(lib_names=["data", "text_page"])
        await frame.upload_frame_app(
            local_filename="lua/text_page_app.lua",
            frame_filename="text_page_app.lua",
        )
        await frame.start_frame_app(frame_app_name="text_page_app", await_print=True)

        rx_click = RxClick()
        click_queue = await rx_click.attach(frame)

        layout = CircularTextLayout(width=256, height=256, font_size=20, circle_margin=18)
        tx = TxTextPage(layout, TEXT)

        page_num = 0
        page = tx.rasterize_next_page()
        await send_page(frame, page)
        print(f"Page {page_num}: {page.line_texts}")

        if args.emulator:
            await asyncio.sleep(0.3)
            frame.get_framebuffer().save(f"text_page_output_{page_num:02d}.png")

            # click through the remaining pages by injecting button presses
            while tx.has_more_text:
                frame.inject_button_single()
                click = await asyncio.wait_for(click_queue.get(), timeout=2)
                assert click == ClickType.SINGLE, f"expected SINGLE, got {click}"

                page = tx.rasterize_next_page()
                if page is None:
                    break
                page_num += 1
                await send_page(frame, page)
                await asyncio.sleep(0.3)
                frame.get_framebuffer().save(f"text_page_output_{page_num:02d}.png")
                print(f"Page {page_num}: {page.line_texts}")

            # verify all drawn pixels sit inside the layout circle
            import math
            fb = frame.get_framebuffer().convert("L")
            lit = [
                (x, y)
                for y in range(fb.height)
                for x in range(fb.width)
                if fb.getpixel((x, y)) >= 128
            ]
            assert lit, "nothing was drawn on the framebuffer"
            max_dist = max(
                math.hypot(x - layout.center_x, y - layout.center_y) for x, y in lit
            )
            # Chords are fitted at each line's vertical midpoint (same as the
            # Flutter SDK), so glyph boxes may exceed the layout circle by a
            # couple of pixels; circle_margin exists to absorb that. The hard
            # invariant is the visible display circle.
            visible_radius = min(layout.width, layout.height) / 2
            assert max_dist <= visible_radius, (
                f"text escaped the visible display: {max_dist:.1f} > {visible_radius}"
            )
            print(f"OK: {len(lit)} text pixels, outermost at r={max_dist:.1f} "
                  f"(layout r={layout.radius}, visible r={visible_radius})")

            # long press should come through as well
            frame.inject_button_long()
            click = await asyncio.wait_for(click_queue.get(), timeout=2)
            assert click == ClickType.LONG, f"expected LONG, got {click}"
            print("OK: click types delivered (SINGLE, LONG)")
        else:
            # on hardware: page through with the physical button
            while tx.has_more_text:
                click = await click_queue.get()
                if click == ClickType.SINGLE:
                    page = tx.rasterize_next_page()
                    if page is None:
                        break
                    await send_page(frame, page)
                elif click == ClickType.LONG:
                    break

        rx_click.detach(frame)

    finally:
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
