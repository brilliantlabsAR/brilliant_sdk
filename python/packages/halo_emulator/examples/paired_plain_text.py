"""
paired_plain_text.py — host-side client for lua/plain_text_app.lua.

Demonstrates the full brilliant_msg message-passing pattern:
  - Upload standard Lua libraries (data.min.lua, plain_text.min.lua)
  - Upload and start a Lua app
  - Send TxPlainText messages; the app renders them on the display

This example uses brilliant_msg message types (TxPlainText) unchanged on both
the emulator and real hardware.

Usage:
    python paired_plain_text.py                # real Halo hardware
    python paired_plain_text.py --emulator     # emulator, saves PNGs for each message

Requirements:
    pip install brilliant-msg halo-emulator
"""

import asyncio
import argparse

from brilliant_msg import TxPlainText            # type: ignore[import]


MESSAGES = [
    "Hello\nHalo!",
    "Python + Lua",
    "frame_msg\nprotocol",
    "Emulator\nor hardware\n— same code",
    " ",
]

TEXT_FLAG = 0x0a


async def main() -> None:
    parser = argparse.ArgumentParser(description="Plain-text display demo")
    parser.add_argument("--emulator", action="store_true", help="Use the emulator")
    args = parser.parse_args()

    # ---- connection ----
    if args.emulator:
        from halo_emulator import HaloEmulator, EmulatorBrilliantMsg
        emu = HaloEmulator(sandbox_dir="./lua")
        frame = EmulatorBrilliantMsg(emu)
    else:
        from brilliant_msg import BrilliantMsg          # type: ignore[import]
        frame = BrilliantMsg()

    try:
        await frame.connect()

        if not args.emulator:
            # On real hardware, show a loading message during upload
            await frame.print_short_text("Loading...")

        # ---- upload Lua libraries and app ----
        # upload_stdlua_libs copies data.min.lua and plain_text.min.lua from
        # the installed brilliant_msg package into the sandbox (or onto the device).
        await frame.upload_stdlua_libs(lib_names=["data", "plain_text"])
        await frame.upload_frame_app(
            local_filename="lua/plain_text_app.lua",
            frame_filename="plain_text_app.lua",
        )

        frame.attach_print_response_handler()

        # Start the app and wait for it to signal ready ("print(0)")
        await frame.start_frame_app(frame_app_name="plain_text_app", await_print=True)

        # ---- send messages ----
        for i, text in enumerate(MESSAGES):
            print(f"Sending: {text!r}")
            await frame.send_message(TEXT_FLAG, TxPlainText(text).pack())

            if args.emulator:
                await asyncio.sleep(0.3)   # let Lua render
                frame.get_framebuffer().save(f"plain_text_output_{i:02d}.png")
                print(f"  Saved plain_text_output_{i:02d}.png")
            else:
                await asyncio.sleep(2.0)   # display each message for 2s on hardware

        frame.detach_print_response_handler()

    finally:
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
