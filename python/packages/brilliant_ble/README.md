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
from brilliant_ble import BrilliantBle

async def main():
    frame = BrilliantBle()

    try:
        name = await frame.connect()
        print(f"Connected to {name}")

        await frame.send_lua("frame.display.text('Hello, World!', 1, 1);frame.display.show();print(nil)", await_print=True)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
```
