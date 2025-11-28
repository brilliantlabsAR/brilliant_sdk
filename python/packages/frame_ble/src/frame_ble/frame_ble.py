import asyncio
import os

from bleak import BleakClient, BleakScanner, BleakError
from typing import Final
from enum import Enum

class BrilliantDeviceType(Enum):
    FRAME = "Frame"
    HALO = "Halo"
    UNKNOWN = "Unknown"

class FrameBle:
    """
    Class for managing a connection and transferring data to and
    from the Brilliant Labs Frame device over Bluetooth LE using the Bleak library.
    """

    _SERVICE_UUID = "7a230001-5475-a6a4-654c-8431f6ad49c4"
    _TX_CHARACTERISTIC_UUID = "7a230002-5475-a6a4-654c-8431f6ad49c4"
    _RX_CHARACTERISTIC_UUID = "7a230003-5475-a6a4-654c-8431f6ad49c4"
    _AUDIO_TX_CHARACTERISTIC_UUID = "7a230005-5475-a6a4-654c-8431f6ad49c4"

    def __init__(self):
        self._awaiting_print_response = False
        self._awaiting_data_response = False
        self._client = None
        self._print_response = asyncio.Queue()
        self._data_response = asyncio.Queue()
        self._tx_characteristic = None
        self._rx_characteristic = None
        self._audio_tx_characteristic = None
        self._user_data_response_handler = lambda: None
        self._user_disconnect_handler = lambda: None
        self._user_print_response_handler = lambda: None
        self._type = BrilliantDeviceType.UNKNOWN

    @property
    def type(self):
        """
        Returns the type of the Brilliant device.
        """
        return self._type

    def _disconnect_handler(self, _):
        self._user_disconnect_handler()
        self.__init__()

    async def _notification_handler(self, _, data):
        if data[0] == 1:
            # Use memoryview to avoid copying
            data_view = memoryview(data)[1:]

            if self._awaiting_data_response:
                self._awaiting_data_response = False
                await self._data_response.put(data_view)

            # call the user response handler on all incoming notifications
            if self._user_data_response_handler is not None:
                if asyncio.iscoroutinefunction(self._user_data_response_handler):
                    await self._user_data_response_handler(data_view)
                else:
                    self._user_data_response_handler(data_view)
        else:
            # decode the string data only once
            decoded = data.decode()

            if self._awaiting_print_response:
                self._awaiting_print_response = False
                await self._print_response.put(decoded)

            # call the user response handler on all incoming notifications
            if self._user_print_response_handler is not None:
                if asyncio.iscoroutinefunction(self._user_print_response_handler):
                    await self._user_print_response_handler(decoded)
                else:
                    self._user_print_response_handler(decoded)

    async def connect(
        self,
        name=None,
        timeout=10,
        print_response_handler=lambda _: None,
        data_response_handler=lambda _: None,
        disconnect_handler=lambda: None,
    ):
        """
        Connects to the first Frame device discovered,
        optionally matching a specified name e.g. "Frame AB",
        or throws an Exception if a matching Frame is not found within timeout seconds.

        `name` can optionally be provided as the local name containing the
        2 digit ID shown on Frame, in order to only connect to that specific device.
        The value should be a string, for example `"Frame 4F"`

        `print_response_handler` and `data_response_handler` can be provided and
        will be called whenever data arrives from the device asynchronously.

        `disconnect_handler` can be provided to be called to run
        upon a disconnect.
        """

        self._user_disconnect_handler = disconnect_handler
        self._user_print_response_handler = print_response_handler
        self._user_data_response_handler = data_response_handler

        # Create a scanner with a filter for our service UUID and optional name
        device = await BleakScanner.find_device_by_filter(
            lambda d, _: d.name is not None and (name is None or d.name == name),
            timeout=timeout,
            service_uuids=[self._SERVICE_UUID]
        )

        if not device:
            raise Exception("No matching Frame device found")

        self._client = BleakClient(
            device,
            disconnected_callback=self._disconnect_handler,
            winrt=dict(use_cached_services=False)
        )

        try:
            await self._client.connect()
            # Workaround to acquire MTU size because Bleak doesn't do it automatically when using BlueZ backend
            if self._client._backend.__class__.__name__ == "BleakClientBlueZDBus":
                await self._client._backend._acquire_mtu()
        except BleakError as ble_error:
            raise Exception(f"Error connecting: {ble_error}")

        service = self._client.services.get_service(
            self._SERVICE_UUID,
        )

        self._tx_characteristic = service.get_characteristic(
            self._TX_CHARACTERISTIC_UUID,
        )

        self._rx_characteristic = service.get_characteristic(
            self._RX_CHARACTERISTIC_UUID,
        )

        self._audio_tx_characteristic = service.get_characteristic(
            self._AUDIO_TX_CHARACTERISTIC_UUID,
        )

        if self._tx_characteristic is not None:
            self._type = BrilliantDeviceType.HALO
        else:
            self._type = BrilliantDeviceType.FRAME

        try:
            await self._client.start_notify(
                self._RX_CHARACTERISTIC_UUID,
                self._notification_handler,
            )
        except Exception as ble_error:
            raise Exception(f"Error subscribing for notifications: {ble_error}")

        return device.name

    async def disconnect(self):
        """
        Disconnects from the device.
        """
        if (self._client is not None):
            await self._client.disconnect()
        self._disconnect_handler(None)

    def is_connected(self):
        """
        Returns `True` if the device is connected. `False` otherwise.
        """
        try:
            return (self._client is not None) and self._client.is_connected
        except AttributeError:
            return False

    def max_lua_payload(self):
        """
        Returns the maximum length of a Lua string which may be transmitted.
        """
        try:
            return self._client.mtu_size - 3
        except AttributeError:
            return 0

    def max_data_payload(self):
        """
        Returns the maximum length of a raw bytearray which may be transmitted.
        """
        try:
            return self._client.mtu_size - 4
        except AttributeError:
            return 0

    async def _transmit(self, data, show_me=False):
        if show_me:
            print(data)  # TODO make this print nicer

        if len(data) > self._client.mtu_size - 3:
            raise Exception("payload length is too large")

        await self._client.write_gatt_char(self._tx_characteristic, data, response=True)

    async def send_lua(self, string: str, show_me=False, await_print=False, timeout=5):
        """
        Sends a Lua string to the device. The string length must be less than or
        equal to `max_lua_payload()`.

        If `await_print=True`, the function will block until a Lua print()
        occurs, or a timeout (in seconds).

        If `show_me=True`, the exact bytes send to the device will be printed.
        """

        # set the awaiting status before we transmit
        self._awaiting_print_response = await_print

        await self._transmit(string.encode(), show_me=show_me)

        if await_print:
            try:
                return await asyncio.wait_for(self._print_response.get(), timeout=timeout)
            except asyncio.TimeoutError:
                raise Exception("device didn't respond")

    async def send_data(self, data: bytearray, show_me=False, await_data=False, timeout=5):
        """
        Sends raw data to the device. The payload length must be less than or
        equal to `max_data_payload()`.

        If `await_data=True`, the function will block until a data response
        occurs, or a timeout (in seconds).

        If `show_me=True`, the exact bytes send to the device will be printed.
        """
        # set the awaiting status before we transmit
        self._awaiting_data_response = await_data

        await self._transmit(bytearray(b"\x01") + data, show_me=show_me)

        if await_data:
            try:
                return await asyncio.wait_for(self._data_response.get(), timeout=timeout)
            except asyncio.TimeoutError:
                raise Exception("device didn't respond")

    async def send_audio(self, data: bytearray, await_bt_response=False):
        """
        Sends audio data to the custom audio characteristic of the device.
        await_bt_response corresponds to bluetooth "writeWithResponse", so
        a bluetooth-level ACK will be required for each write (defaults to False)

        Note:
        Ensure that whole LC3 frames fit within MTU if sending LC3,
        or even numbers of samples are provided in the case of PCM
        If data exceeds a single packet payload (mtu-3) the audio packet is silently dropped
        """
        mtu = self._client.mtu_size - 3
        if len(data) > mtu:
            return
        # stream audio as write-without-response (response=False)
        await self._client.write_gatt_char(self._audio_tx_characteristic, data, response=await_bt_response)

    async def send_reset_signal(self, show_me=False):
        """
        Sends a reset signal to the device which will reset the Lua virtual
        machine.

        If `show_me=True`, the exact bytes send to the device will be printed.
        """
        await self._transmit(bytearray(b"\x04"), show_me=show_me)
        # need to give it a moment after the Lua VM reset before it can handle any requests
        await asyncio.sleep(0.2)

    async def send_remove_signal(self, show_me=False):
        """
        Sends a remove signal to the device which will remove the main.lua file from Halo.
        This is only applicable to Halo devices.

        If `show_me=True`, the exact bytes send to the device will be printed.
        """
        await self._transmit(bytearray(b"\x05"), show_me=show_me)
        # need to give it a moment after the Lua VM reset before it can handle any requests
        await asyncio.sleep(0.2)

    async def send_break_signal(self, show_me=False):
        """
        Sends a break signal to the device which will break any currently
        executing Lua script.

        If `show_me=True`, the exact bytes send to the device will be printed.
        """
        await self._transmit(bytearray(b"\x03"), show_me=show_me)
        # need to give it a moment after the break before it can handle any requests
        await asyncio.sleep(0.2)

    async def upload_file_from_string(self, content: str, frame_file_path="main.lua"):
        """
        Uploads a string as frame_file_path. If the file exists, it will be overwritten.

        Args:
            content (str): The string content to upload
            frame_file_path (str): Target file path on the frame
        """
        # Escape special characters
        content = (content.replace("\r", "")
                        .replace("\\", "\\\\")
                        .replace("\n", "\\n")
                        .replace("\t", "\\t")
                        .replace("'", "\\'")
                        .replace('"', '\\"'))

        # Open the file on the frame
        await self.send_lua(
            f"f=frame.file.open('{frame_file_path}','w');print(1)",
            await_print=True
        )

        # Calculate chunk size accounting for the Lua command overhead
        chunk_size: int = self.max_lua_payload() - 22

        # Upload in chunks
        i = 0
        while i < len(content):
            # Calculate initial chunk size
            current_chunk_size = min(chunk_size, len(content) - i)

            # Check for escape sequences at the chunk boundary
            if current_chunk_size < len(content) - i:
                # Look for the last non-escaped backslash in the chunk
                pos = i + current_chunk_size - 1
                while pos > i:
                    # Check if we're in the middle of an escape sequence
                    if content[pos] == '\\' and (pos == i or content[pos-1] != '\\'):
                        # If we find an unescaped backslash, adjust the chunk size
                        current_chunk_size = pos - i
                        break
                    pos -= 1

            chunk: str = content[i:i + current_chunk_size]
            await self.send_lua(f'f:write("{chunk}");print(1)', await_print=True)
            i += current_chunk_size

        # Close the file
        await self.send_lua("f:close();print(nil)", await_print=True)

    async def upload_file(self, local_file_path: str, frame_file_path="main.lua"):
        """
        Uploads a local file to the frame. If the target file exists, it will be overwritten.

        Args:
            local_file_path (str): Path to the local file to upload. Must exist.
            frame_file_path (str): Target file path on the frame

        Raises:
            FileNotFoundError: If local_file_path doesn't exist
        """
        if not os.path.exists(local_file_path):
            raise FileNotFoundError(f"Local file not found: {local_file_path}")

        with open(local_file_path, "r") as f:
            content = f.read()

        await self.upload_file_from_string(content, frame_file_path)

    async def send_message(self, msg_code: int, payload: bytes, show_me: bool=False) -> None:
        """
        Send a large payload in chunks determined by BLE MTU size.

        Args:
            msg_code (int): Message type identifier (0-255)
            payload (bytes): Data to be sent
            show_me (bool): If True, the exact bytes send to the device will be printed

        Raises:
            ValueError: If msg_code is not in range 0-255 or payload size exceeds 65535

        Note:
            First packet format: [msg_code(1), size_high(1), size_low(1), data(...)]
            Other packets format: [msg_code(1), data(...)]
        """
        # Constants
        HEADER_SIZE: Final = 3  # msg_code + 2 bytes size
        SUBSEQUENT_HEADER_SIZE: Final = 1  # just msg_code
        MAX_TOTAL_SIZE: Final = 65535  # 2^16 - 1, maximum size that fits in 2 bytes

        # Validation
        if not 0 <= msg_code <= 255:
            raise ValueError(f"Message code must be 0-255, got {msg_code}")

        total_size = len(payload)
        if total_size > MAX_TOTAL_SIZE:
            raise ValueError(f"Payload size {total_size} exceeds maximum {MAX_TOTAL_SIZE} bytes")

        # Calculate maximum chunk sizes
        max_first_chunk = self.max_data_payload() - HEADER_SIZE
        max_chunk_size = self.max_data_payload() - SUBSEQUENT_HEADER_SIZE

        # Pre-allocate buffer for maximum sized packets
        buffer = bytearray(self.max_data_payload())

        # Send first chunk
        first_chunk_size = min(max_first_chunk, total_size)
        buffer[0] = msg_code
        buffer[1] = total_size >> 8
        buffer[2] = total_size & 0xFF
        buffer[HEADER_SIZE:HEADER_SIZE + first_chunk_size] = payload[:first_chunk_size]
        await self.send_data(memoryview(buffer)[:HEADER_SIZE + first_chunk_size], show_me=show_me, await_data=True)
        sent_bytes = first_chunk_size

        # Send remaining chunks
        if sent_bytes < total_size:
            # Set message code in the reusable buffer
            buffer[0] = msg_code

            while sent_bytes < total_size:
                remaining = total_size - sent_bytes
                chunk_size = min(max_chunk_size, remaining)

                # Copy next chunk into the pre-allocated buffer
                buffer[SUBSEQUENT_HEADER_SIZE:SUBSEQUENT_HEADER_SIZE + chunk_size] = \
                    payload[sent_bytes:sent_bytes + chunk_size]

                # Send only the used portion of the buffer
                await self.send_data(memoryview(buffer)[:SUBSEQUENT_HEADER_SIZE + chunk_size], show_me=show_me, await_data=True)
                sent_bytes += chunk_size
