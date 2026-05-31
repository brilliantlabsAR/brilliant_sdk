# Brilliant Message Package

A Python package for handling rich application-level messages for [Brilliant Labs](https://brilliant.xyz/) Frame and Halo devices, including sprites, text, audio, IMU data, and photos.

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/).

[Examples on GitHub](https://github.com/brilliantlabsAR/brilliant_sdk/tree/main/python/packages/brilliant_msg/examples).

## Installation

```bash
uv add brilliant-msg
```

## Usage

```python
import asyncio
from pathlib import Path

from brilliant_msg import BrilliantMsg, TxSprite

async def main():
    """
    Displays sample images on the Frame display.

    The images are indexed (palette) PNG images, in 2, 4, and 16 colors (that is, 1-, 2- and 4-bits-per-pixel).
    """
    frame = BrilliantMsg()
    try:
        await frame.connect()

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that handle data accumulation and sprite parsing
        await frame.upload_stdlua_libs(lib_names=['data', 'sprite'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/sprite_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        await frame.start_frame_app()

        # send the 1-bit image to Frame in chunks
        sprite = TxSprite.from_indexed_png_bytes(Path("images/logo_1bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())

        # send a 2-bit image
        sprite = TxSprite.from_indexed_png_bytes(Path("images/street_2bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())

        # send a 4-bit image
        sprite = TxSprite.from_indexed_png_bytes(Path("images/hotdog_4bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())

        await asyncio.sleep(5.0)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
```

## Running Tests

From the workspace root:

```bash
cd python
uv sync --all-packages --extra tests
uv run pytest packages/brilliant_msg/tests/
```

The test suite covers all Tx message packing (TxCode, TxPlainText, TxSpriteCoords,
TxCaptureSettings, TxAutoExpSettings, TxSprite bit-packing and factory methods,
TxImageSpriteBlock, TxTextSpriteBlock) and Rx message parsing (RxAudio WAV
conversion, RxMeteringData, RxAutoExpResult, RxIMU including IMUData pitch/roll
and SensorBuffer smoothing, RxTap, and BrilliantMsg handler dispatch). No hardware
is required.