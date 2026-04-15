# Frame Message Package

A Python package for handling rich application-level messages for the [Brilliant Labs Frame](https://brilliant.xyz/), including sprites, text, audio, IMU data, and photos.

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/).

[Examples repo on GitHub](https://github.com/CitizenOneX/frame_examples_python).

## Installation

```bash
uv add frame-msg
```

## Usage

```python
import asyncio
from pathlib import Path

from frame_msg import FrameMsg, TxSprite

async def main():
    """
    Displays sample images on the Frame display.

    The images are indexed (palette) PNG images, in 2, 4, and 16 colors (that is, 1-, 2- and 4-bits-per-pixel).
    """
    frame = FrameMsg()
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

## Acknowledgements

* An early port of [TxSprite](https://github.com/CitizenOneX/frame_msg/blob/main/lib/tx/sprite.dart) from Flutter to Python was contributed by [David Khachatryan](https://github.com/KhachDavid) - _thanks!_