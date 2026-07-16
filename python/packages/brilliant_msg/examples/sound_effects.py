import asyncio
import argparse
import random
import traceback

from brilliant_msg import BrilliantMsg
from brilliant_ble import BrilliantDeviceType
from tx_sound_effect import TxSoundEffect

# firmware sound presets available via frame.sound.play()
EFFECTS = ['pickup', 'laser', 'explosion', 'powerup', 'hit', 'jump', 'blip']

PLAY_SOUND_MSG = 0x20

# firmware sounds default to 1000ms duration and only one can play at a time,
# so space plays out a little further than that
SOUND_GAP = 1.2

async def main():
    """
    Play the firmware's built-in sfxr sound effect presets through the Halo speaker.
    Each sound is generated from a preset name and a 32-bit seed, so the same
    seed always reproduces the same sound.
    """
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantMsg()
    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        if frame.type != BrilliantDeviceType.HALO:
            print("Speaker is a Halo-only feature")
            return

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that handle data accumulation
        await frame.upload_stdlua_libs(lib_names=['data'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/sound_effects_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        # If we assigned this handler before the frameside app was running,
        # any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
        # the handler now we'll see any lua exceptions (or stdout print statements)
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        # It signals that it is ready by sending something on the string response channel.
        await frame.start_frame_app()

        # NOTE: Now that the Frameside app has started there is no need to send snippets of Lua
        # code directly (in fact, we would need to send a break_signal if we wanted to because
        # the main app loop on Frame is running).
        # From this point we do message-passing with first-class types and send_message() (or send_data())

        # play a random variation of each of the firmware presets
        for effect in EFFECTS:
            seed = random.getrandbits(32)
            print(f"Playing {effect} ({seed})")
            await frame.send_message(PLAY_SOUND_MSG, TxSoundEffect(effect=effect, seed=seed).pack())
            await asyncio.sleep(SOUND_GAP)

        # the same effect and seed always reproduce the same sound
        print("Playing the same jump sound twice")
        for _ in range(2):
            await frame.send_message(PLAY_SOUND_MSG, TxSoundEffect(effect='jump', seed=123456).pack())
            await asyncio.sleep(SOUND_GAP)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    except TimeoutError as e:
        print(f"Timeout error occurred: {e}")
    except Exception as e:
        print(f"An error occurred: {e}")
        print(f"Traceback: {traceback.format_exc()}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
