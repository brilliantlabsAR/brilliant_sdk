# Python quickstart

```bash
pip install brilliant-sdk        # or brilliant-ble / brilliant-msg separately
```

Two files. Host program (`app.py`):

```python
"""Show text on the glasses via a device-side Lua app."""
import asyncio
from brilliant_msg import BrilliantMsg, TxPlainText

TEXT_MSG = 0x0a  # must match the Lua app

async def main():
    frame = BrilliantMsg()
    try:
        await frame.connect()                      # connect(name="Halo AB") to target one device
        await frame.upload_stdlua_libs(lib_names=['data', 'plain_text'])
        await frame.upload_frame_app(local_filename="lua/my_frame_app.lua")
        frame.attach_print_response_handler()      # device print()/errors -> stdout
        await frame.start_frame_app()              # blocks until the app prints ready

        await frame.send_message(TEXT_MSG, TxPlainText("Hello!", x=100, y=120).pack())
        await asyncio.sleep(2.0)

        frame.detach_print_response_handler()
        await frame.stop_frame_app()
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
```

Device app (`lua/my_frame_app.lua`):

```lua
local data = require('data.min')
local plain_text = require('plain_text.min')

TEXT_MSG = 0x0a

function app_loop()
    if frame.HARDWARE_VERSION ~= 'Frame' then
        frame.display.power_save(false)          -- Halo: wake the display
    end
    print('app running')                          -- releases start_frame_app()
    while true do
        rc, err = pcall(function()
            for _, item in ipairs(data.process_raw_items()) do
                local flag, raw = item[1], item[2]
                if flag == TEXT_MSG then
                    local t = plain_text.parse_plain_text(raw)
                    frame.display.text(t.string, t.x, t.y)
                    if frame.HARDWARE_VERSION == 'Frame' then
                        frame.display.show()      -- Frame: flip the buffer
                    end
                end
            end
            frame.sleep(0.1)
        end)
        if rc == false then print(err) break end  -- includes the break signal
    end
end

app_loop()
```

Run: `python app.py` (first device found) — add `--name`-style targeting via
`connect(name=...)`.

## Read next

- `python/packages/brilliant_msg/examples/plain_text.py` — this pattern with
  full commentary; `EXAMPLES.md` in the same directory indexes all 34 examples
  by message type.
- `python/packages/brilliant_msg/src/brilliant_msg/brilliant_msg.py` (194
  lines) — the whole `BrilliantMsg` API surface.
- Receivers: `RxPhoto`, `RxAudio`, `RxIMU`, `RxTap` attach to the data
  channel; see `camera.py`, `audio_clip.py`, `imu.py`, `multi_tap.py`.
- API docs: https://brilliant-msg.readthedocs.io/ ·
  https://brilliant-ble.readthedocs.io/
