"""
repl_hello.py — REPL-style display commands, no Lua app file required.

Sends Lua snippets directly to the device (or emulator), just like typing
at a Halo REPL prompt.  This is useful for quick one-off display tests or
scripted setup before uploading a full app.

Usage:
    python repl_hello.py                # real Halo hardware (requires brilliant-ble)
    python repl_hello.py --emulator     # emulator, saves output.png
"""

import asyncio
import argparse


async def main() -> None:
    parser = argparse.ArgumentParser(description="REPL-style Halo display demo")
    parser.add_argument("--emulator", action="store_true", help="Use the emulator")
    args = parser.parse_args()

    # ---- connection ----
    # Swap these two lines to switch between emulator and real hardware:
    if args.emulator:
        from halo_emulator import HaloEmulator, EmulatorBrilliantMsg
        emu = HaloEmulator()
        frame = EmulatorBrilliantMsg(emu)
    else:
        from brilliant_msg import BrilliantMsg          # type: ignore[import]
        frame = BrilliantMsg()

    try:
        await frame.connect()

        # ---- Lua REPL commands ----
        # Each send_lua() call is executed immediately, as if typed at the REPL.
        # The display state is cumulative until clear() is called.

        await frame.send_lua("frame.display.clear(0)")

        # White border
        await frame.send_lua(
            "frame.display.rect(4, 4, 248, 248, 0xFFFFFF, false)"
        )

        # Greeting text
        await frame.send_lua(
            "frame.display.text('Hello, Halo!', 30, 100, 0xFFFFFF)"
        )

        # Battery level in the corner
        await frame.send_lua(
            "frame.display.text(frame.battery_level() .. '%', 10, 230, 0x00FF00)"
        )

        # Flush to display
        await frame.send_lua("frame.display.show()")

        # ---- emulator: save the framebuffer ----
        if args.emulator:
            out = "repl_hello_output.png"
            emu.get_framebuffer().save(out)
            print(f"Saved {out}")
        else:
            # On real hardware, keep the display visible for a few seconds
            await asyncio.sleep(5)

    finally:
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
