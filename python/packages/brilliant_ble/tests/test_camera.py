from aioconsole import ainput
from brilliant_ble import BrilliantBle
import asyncio
import time

image_buffer = b""
image_suffix = 1


def receive_data(data):
    global image_buffer
    global image_suffix
    print(
        f"Received {str(len(data))} bytes - {str(len(image_buffer))} total - {str(len(data)-1)} image"
    )
    if len(data) == 1:
        with open(f"test_camera_image_{image_suffix}.jpg", "wb") as f:
            print(f"Image {image_suffix} - Received {str(len(image_buffer)-1)} bytes")
            f.write(image_buffer)
            image_buffer = b""
            image_suffix += 1
        return
    image_buffer += data[1:]


async def main():

    lua_script = """

    function transfer()
        while frame.camera.image_ready() == false do
            -- wait
        end

        while true do
            local i = frame.camera.read(frame.bluetooth.max_length() - 1)
            if (i == nil) then
                break
            else
                while true do
                    if pcall(frame.bluetooth.send, '0' .. i) then
                        break
                    end
                end
            end
        end

        while true do
            if pcall(frame.bluetooth.send, '0') then
                break
            end
        end
    end

    frame.camera.power_save(false)

    frame.camera.capture { resolution = 640, quality = 'LOW' }; transfer()

    print("Done - Press enter to finish")
    """

    # Connect to bluetooth and upload file
    b = BrilliantBle()
    await b.connect(
        print_response_handler=lambda s: print(s),
        data_response_handler=receive_data,
    )

    print("Uploading script")

    await b.upload_file_from_string(lua_script, "main.lua")
    await b.send_reset_signal()

    # Wait until a keypress
    print(
        "Upload finished. Press enter to start capture."
    )
    await ainput("")

    await b.send_break_signal()
    await b.disconnect()


loop = asyncio.new_event_loop()
loop.run_until_complete(main())
