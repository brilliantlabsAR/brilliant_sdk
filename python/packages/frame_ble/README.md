# frame-ble

Low-level library for Bluetooth LE connection to [Brilliant Labs Frame](https://brilliant.xyz/)

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/).

[Examples repo on GitHub](https://github.com/CitizenOneX/frame_examples_python).

## Installation

```bash
uv add frame-ble
```

## Usage

```python
import asyncio
from frame_ble import FrameBle

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        await frame.send_lua("frame.display.text('Hello, Frame!', 1, 1);frame.display.show();print(nil)", await_print=True)

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Frame: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())
```
