from typing import List
from importlib.resources import files

from brilliant_ble import BrilliantBle, BrilliantDeviceType
from typing import Callable

class BrilliantMsg:
    """
    A high-level library for interacting with Brilliant Labs Frame by passing structured messages
    between a Frameside app and a hostside app.

    """
    def __init__(self):
        """Initialize the BrilliantMsg class with a new BrilliantBle instance and a dictionary for registered data response handlers."""
        self.ble = BrilliantBle()
        self.data_response_handlers = {}

    async def connect(self, initialize:bool=True, name=None):
        """
        Connect to the Frame device and optionally run the initialization sequence.

        Args:
            initialize (bool): If True, runs the break/reset/break sequence after connecting.
                             Defaults to True.
            name (str): Optional device local name (e.g. "Halo 08") to connect to
                             only that specific device. If None, connects to the
                             first Halo/Frame discovered.

        Returns:
            str: The BLE local name of the connected device (e.g. "Halo 08"),
                 also available afterwards as `self.name`.

        Raises:
            Any exceptions from the underlying BrilliantBle connection
        """
        try:
            device_name = await self.ble.connect(name=name, data_response_handler=self._handle_data_response)

            if initialize:
                # Send break signal in case an application loop is running
                await self.ble.send_break_signal()

                # Reset signal to restart Lua VM and initialize memory
                await self.ble.send_reset_signal()

                # Another break signal in case of auto-starting main.lua
                await self.ble.send_break_signal()

                # Soak up any 'interrupted'/reboot banner the break/reset/break
                # sequence produced, so the caller's first
                # send_lua(await_print=True) gets a clean channel. Bounded, and
                # a no-op (one short quiet window) on an idle device.
                await self.ble.drain_print_channel()

            return device_name

        except Exception as e:
            # If anything fails during connection or initialization,
            # ensure we're disconnected and re-raise the exception
            if self.ble.is_connected():
                await self.ble.disconnect()
            raise e


    async def disconnect(self):
        """Disconnect from the Frame device"""
        if self.ble.is_connected():
            await self.ble.disconnect()

    def is_connected(self):
        """Check if currently connected to the Frame device."""
        return self.ble.is_connected()

    async def print_short_text(self, text:str=''):
        """
        Convenience wrapper around `frame.display.text()` that can only be used
        prior to the main frame_app starting (e.g. immediately after connection).
        """
        sanitized_text = text.replace("'", "\\'").replace("\n", "")
        lua_command = ""
        if (self.ble.type == BrilliantDeviceType.FRAME):
            lua_command = f"frame.display.text('{sanitized_text}',1,1);frame.display.show();print(0)"
        else:
            lua_command = f"frame.display.clear();frame.display.text('{sanitized_text}',50,50);print(0)"

        await self.ble.send_lua(lua_command, await_print=True)

    async def upload_stdlua_libs(self, lib_names: List[str]=['data'], minified: bool=True):
        """Send the specified standard frame-msg Lua files to Frame that are used by the frame_app, e.g. ['data', 'camera'] """
        for stdlua in lib_names:
            suffix = ".min" if minified else ""
            await self.ble.upload_file_from_string(files("brilliant_msg").joinpath(f"lua/{stdlua}{suffix}.lua").read_text(), f"{stdlua}{suffix}.lua")

    async def upload_frame_app(self, local_filename: str, frame_filename: str='frame_app.lua'):
        """ Send the main lua application from this project to Frame that will run the app (but doesn't run the file)"""
        # We rename the file slightly when we copy it, although it isn't necessary
        await self.ble.upload_file(local_filename, frame_filename)

    async def start_frame_app(self, frame_app_name:str='frame_app', await_print:bool=True):
        """
        'require' the main lua file to run it

        Note: This require() doesn't return - frame_app.lua has a main loop,
        so we can't put a 'print(0)' after the require() statement and wait for it to print,
        however if our main loop prints something (even a byte) once it has started up,
        then the await_print can be used to determine that the frameside app is ready
        rather than waiting for an app-dependent amount of time,
        or sending messages to Frame too early.
        Set await_print to False if the Frame app should be asynchronously started
        and without waiting for any printed confirmation that the frameside app is ready.
        """
        await self.ble.send_lua(f"require('{frame_app_name}')", await_print=await_print)

    async def stop_frame_app(self, reset=True):
        """
        Sends a break signal to terminate the running main loop on Frame, if applicable.
        A custom app may prefer to send a specific TxCode to the Frameside app to instruct it
        to shut down cleanly, but a break signal will also be caught by the exception handler
        of the main loop and is enough to clean up the display, release memory etc.

        If `reset` is True (default), then also send a reset signal that will reinitialize the Lua VM
        and boot into a saved `main.lua`, if present.
        """
        await self.ble.send_break_signal()
        if reset:
            await self.ble.send_reset_signal()

    def attach_print_response_handler(self, handler=print):
        """Attach the print response handler so we can see stdout from Frame Lua print() statements"""
        self.ble._user_print_response_handler = handler

    def detach_print_response_handler(self):
        """Detach the print response handler so we no longer see stdout from Frame Lua print() statements"""
        self.ble._user_print_response_handler = None

    async def send_message(self, msg_code: int, payload: bytes, show_me: bool=False) -> None:
        """
        Sends a structured message from hostside to the Frameside app, identified by the specified msg_code.
        For example, if the frame_app is expecting a TxCaptureSettings message on msg_code 0x0d
        to initiate a photo capture, you might send:
        `frame.send_message(0x0d, TxCaptureSettings(resolution=720).pack())`
        Wraps the brilliant_ble function of the same name
        """
        await self.ble.send_message(msg_code, payload, show_me)

    def register_data_response_handler(self, subscriber, msg_codes: List[int], handler: Callable[[bytes], None]):
        """
        Register a handler for a subscriber that is interested in specific msg codes.

        Args:
            subscriber: The subscriber object.
            msg_codes (List[int]): List of single byte msg codes the subscriber is interested in.
            handler: The handler function to receive the data.
        """
        for code in msg_codes:
            if code not in self.data_response_handlers:
                self.data_response_handlers[code] = []
            self.data_response_handlers[code].append((subscriber, handler))

    def unregister_data_response_handler(self, subscriber):
        """
        Unregister a subscriber from receiving data responses.

        Args:
            subscriber: The subscriber object to unregister.
        """
        for code in list(self.data_response_handlers.keys()):
            self.data_response_handlers[code] = [
                (sub, handler) for sub, handler in self.data_response_handlers[code] if sub != subscriber
            ]
            if not self.data_response_handlers[code]:
                del self.data_response_handlers[code]

    async def _handle_data_response(self, data: bytes):
        """
        Internal method to handle incoming data responses and dispatch to the appropriate handlers.

        Args:
            data (bytes): The incoming data response.
        """
        if data:
            msg_code = data[0]
            if msg_code in self.data_response_handlers:
                for subscriber, handler in self.data_response_handlers[msg_code]:
                    # not awaited, synchronous call
                    handler(data)

    def __getattr__(self, name):
        """
        Delegate any unknown attributes to the underlying BrilliantBle instance.
        This allows direct access to all BrilliantBle methods while keeping the
        wrapper transparent.
        """
        return getattr(self.ble, name)
