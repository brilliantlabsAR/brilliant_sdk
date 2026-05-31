# brilliant-ble

Low-level library for Bluetooth LE connection to [Brilliant Labs](https://brilliant.xyz/) Frame and Halo devices.

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/).

[Examples on GitHub](https://github.com/brilliantlabsAR/brilliant_sdk/tree/main/python/packages/brilliant_ble/examples).

## Installation

```bash
uv add brilliant-ble
```

## Usage

```python
import asyncio
from brilliant_ble import FrameBle

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        await frame.send_lua("frame.display.text('Hello, World!', 1, 1);frame.display.show();print(nil)", await_print=True)

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())
```
