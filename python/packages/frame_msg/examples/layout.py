import asyncio

from frame_msg import FrameMsg, TxCode
from frame_ble import BrilliantDeviceType

async def main():
    """
    Use a simple layout engine to draw in separate regions of the display
    """
    frame = FrameMsg()

    try:
        await frame.connect()

        if frame.type != BrilliantDeviceType.HALO:
            print("layout example is Halo-only")
            await frame.disconnect()
            return
        
        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")
        await frame.ble.send_lua("frame.display.power_save(false);frame.display.brightness(25);print(0)", await_print=True)

        # send the std lua files to Frame that handle data accumulation and text display
        await frame.upload_stdlua_libs(lib_names=['data', 'code'])

        # Upload the helper code for managing the layout
        await frame.ble.upload_file(local_file_path="lua/layout.lua", frame_file_path="layout.lua")

        # Upload the main frame app that will run the layout example
        await frame.upload_frame_app(local_filename="lua/layout_frame_app.lua")

        frame.attach_print_response_handler()

        await frame.start_frame_app()

        print(f"Starting layout")
        
        await asyncio.sleep(8.0)

        print(f"Stopping layout")
        frame.detach_print_response_handler()

        await frame.stop_frame_app()

        await frame.disconnect()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if frame.ble.is_connected:
            await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())