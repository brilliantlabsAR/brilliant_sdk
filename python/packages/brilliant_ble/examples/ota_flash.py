"""
Flashes signed app firmware to a Halo device over the BLE SMP (MCUmgr) OTA service.

Usage:
    python ota_flash.py zephyr.signed.bin                            # one-shot test boot (default)
    python ota_flash.py zephyr.signed.bin --name "Halo AB"           # only connect to this device
    python ota_flash.py zephyr.signed.bin --yes                      # skip the confirmation prompt
    python ota_flash.py zephyr.signed.bin --dangerously-auto-confirm  # upload, confirm, reboot

The connected device name is printed and you are asked to confirm before any
firmware is written, so you don't flash the wrong device.

By default the image is marked for a one-shot test boot: MCUboot reverts to the
previous firmware on the next reboot unless the new image is confirmed:
reconnect and call ota_confirm().

Note: first-time flashing and bootloader flashing still require the Alif wired
tools. This only updates a device that already boots an OTA-enabled app firmware.
"""
import argparse
import asyncio

from brilliant_ble import BrilliantBle, OtaError


async def main():
    parser = argparse.ArgumentParser(description="Flash signed app firmware to a Halo device over BLE SMP OTA")
    parser.add_argument("firmware", help="path to zephyr.signed.bin")
    parser.add_argument("--name", default=None, help='only connect to a device with this exact BLE name, e.g. "Halo AB"')
    parser.add_argument("--yes", action="store_true", help="skip the y/N confirmation prompt")
    parser.add_argument("--dangerously-auto-confirm", action="store_true", help="confirm the image immediately instead of marking it for a one-shot test boot")
    parser.add_argument("--chunk-size", type=int, default=384, help="upload payload bytes per packet (default 384)")
    args = parser.parse_args()

    def progress(sent, total):
        print(f"\rUploaded {sent}/{total} bytes ({sent * 100 // total}%)", end="", flush=True)

    halo = BrilliantBle()

    try:
        name = await halo.connect(name=args.name)
        print(f"Connected to {name}")

        if not args.yes:
            answer = input(f"Flash {args.firmware} to {name!r}? [y/N] ").strip().lower()
            if answer != "y":
                print("Aborted. No firmware was written.")
                return

        image_hash = await halo.ota_flash_firmware(
            args.firmware,
            progress_handler=progress,
            confirm=args.dangerously_auto_confirm,
            chunk_size=args.chunk_size,
        )

        print(f"\nFlashed image with MCUboot hash {image_hash.hex()}")
        if not args.dangerously_auto_confirm:
            print("Image marked for test boot: after verifying the new firmware, reconnect and confirm externally to keep it, or self-confirm within the application firmware after successful boot (boot_write_img_confirmed())")
        print("Device is rebooting...")

    except OtaError as e:
        print(f"\nOTA update failed: {e}")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await halo.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
