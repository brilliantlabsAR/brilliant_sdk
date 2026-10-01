"""Fetch the persisted /lfs log files from a Halo via the frame.log Lua API,
then restart main.lua so the device returns to its normal app.

frame.log is only compiled into firmware builds with logging support, so
released firmware usually does not have it. This example checks for it and
exits cleanly when it is missing.
"""
import asyncio
import argparse

from brilliant_ble import BrilliantBle

# how many characters of a log file to pull back per print()
CHUNK = 180


async def main():
    parser = argparse.ArgumentParser(
        description="Fetch the persisted firmware log files from a Halo over BLE.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB"; defaults to the first device found',
    )
    args = parser.parse_args()
    halo = BrilliantBle()

    try:
        name = await halo.connect(name=args.name)
        print(f"# connected to {name}", flush=True)

        # stop the running app so we have the Lua prompt to ourselves
        await halo.send_break_signal()
        await asyncio.sleep(0.3)

        has_log = await halo.send_lua("print(frame.log ~= nil)",
                                      await_print=True, timeout=10)
        if has_log.strip() != "true":
            print("# this device does not support frame.log - nothing to fetch",
                  flush=True)
            return

        files = await halo.send_lua(
            'local t={} for _,f in ipairs(frame.log.list()) do '
            't[#t+1]=f.name..":"..f.size end print(table.concat(t,","))',
            await_print=True, timeout=10)
        print(f"# log files: {files}", flush=True)

        for entry in [e.strip() for e in files.split(",") if e.strip()]:
            log_name = entry.split()[0].split(":")[0]
            print(f"\n===== {entry} =====", flush=True)
            # Load file into a global, then stream it out in chunks.
            await halo.send_lua(f'__l = frame.log.read("{log_name}") print(#__l)',
                                await_print=True, timeout=15)
            size = int(await halo.send_lua("print(#__l)",
                                           await_print=True, timeout=10))
            i = 1
            while i <= size:
                chunk = await halo.send_lua(
                    f"print(string.sub(__l,{i},{i + CHUNK - 1}))",
                    await_print=True, timeout=10)
                print(chunk, end="", flush=True)
                i += CHUNK
            await halo.send_lua("__l = nil print(1)", await_print=True, timeout=10)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if halo.is_connected():
            print("\n# restarting main.lua", flush=True)
            await halo.send_reset_signal()
        await halo.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
