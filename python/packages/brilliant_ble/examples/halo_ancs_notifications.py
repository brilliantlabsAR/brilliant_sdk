"""Halo-only: install an iOS notification display app (ANCS).

Uploads lua/ancs_notifications.lua as main.lua and restarts the Lua VM.
The app then runs standalone on the Halo: connect the Halo from an iPhone
(bonded/paired) and the phone's notifications are shown on the display,
updating immediately as they arrive (frame.ancs notification callback)
plus a periodic screen refresh.

Note: ANCS is only served by iOS devices. While this computer is the one
connected, the display will show "no ANCS" - disconnect (this script does
so when finished) and connect from the iPhone instead. Requires firmware
with the frame.ancs API (>= 0.8.6).

To remove the app again, run send_remove.py (removes main.lua from the Halo).
"""

import asyncio
from brilliant_ble import BrilliantBle, BrilliantDeviceType

async def main():
    frame = BrilliantBle()

    try:
        await frame.connect()

        if frame.type != BrilliantDeviceType.HALO:
            print("halo_ancs_notifications example is Halo-only")
            await frame.disconnect()
            return

        # Stop any running application so we can talk to the REPL
        await frame.send_break_signal()

        # Sanity-check the firmware has the ANCS API before installing
        await frame.send_lua(
            "print(frame.ancs ~= nil and 'ancs-ok' or 'ancs-missing')",
            await_print=True,
        )

        print("Uploading ancs_notifications.lua as main.lua")
        await frame.upload_file("lua/ancs_notifications.lua", "main.lua")

        # Restart the Lua VM so main.lua starts right away
        await frame.send_reset_signal()

        await frame.disconnect()

        print()
        print("Installed. Now connect the Halo from your iPhone (Brilliant app,")
        print("paired/bonded) - its notifications will appear on the display.")

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())
