import unittest
import asyncio
import os
import sys

from brilliant_ble import BrilliantBle

LUA_DIR = os.path.join(os.path.dirname(__file__), "lua")


class TestBluetooth(unittest.IsolatedAsyncioTestCase):
    async def test_connect_disconnect(self):
        b = BrilliantBle()

        self.assertFalse(b.is_connected())

        device_name = await b.connect()
        self.assertTrue(b.is_connected())

        await b.disconnect()
        self.assertFalse(b.is_connected())

        with self.assertRaises(Exception):
            await b.connect(name="NOT_A_REAL_DEVICE")

        await b.connect(name=device_name)
        await b.disconnect()

    async def test_send_lua(self):
        b = BrilliantBle()
        await b.connect()

        self.assertEqual(await b.send_lua("print('hi')", await_print=True), "hi")

        self.assertIsNone(await b.send_lua("print('hi')"))
        await asyncio.sleep(0.1)

        with self.assertRaises(Exception):
            await b.send_lua("a = 1", await_print=True)

        await b.disconnect()

    async def test_send_data(self):
        b = BrilliantBle()
        await b.connect()
        self.assertIsNone(await b.send_break_signal())

        await b.send_lua(
            "frame.bluetooth.receive_callback((function(d)frame.bluetooth.send(d)end))"
        )

        self.assertEqual(await b.send_data(b"test", await_data=True), b"test")

        self.assertIsNone(await b.send_data(b"test"))
        await asyncio.sleep(0.1)

        await b.send_lua("frame.bluetooth.receive_callback(nil)")

        with self.assertRaises(Exception):
            await b.send_data(b"test", await_data=True)

        await b.disconnect()

    async def test_mtu(self):
        b = BrilliantBle()
        await b.connect()
        self.assertIsNone(await b.send_break_signal())

        max_lua_length = b.max_lua_payload()
        max_data_length = b.max_data_payload()

        self.assertEqual(max_lua_length, max_data_length + 1)

        with self.assertRaises(Exception):
            await b.send_lua("a" * max_lua_length + 1)

        with self.assertRaises(Exception):
            await b.send_data(bytearray(b"a" * max_data_length + 1))

        await b.disconnect()

    async def test_upload_from_file(self):
        b = BrilliantBle()
        await b.connect()
        self.assertIsNone(await b.send_break_signal())

        self.assertIsNone(await b.upload_file(os.path.join(LUA_DIR, "test.lua"), "test.lua"))

        self.assertIsNone(await b.send_lua("require('test')"))
        await asyncio.sleep(1)
        self.assertIsNone(await b.send_break_signal())
        self.assertEqual(await b.send_lua("frame.file.remove('test.lua');print(0)", await_print=True), "0")

        await b.disconnect()

    async def test_upload_from_string(self):
        b = BrilliantBle()
        await b.connect()
        self.assertIsNone(await b.send_break_signal())

        lua_file = """
        for i = 1, 5 do
            frame.display.text('Hello world!', 10, 10)
            frame.display.show()
            frame.sleep(1)
            
            if frame.HARDWARE_VERSION == 'Frame' then
                frame.display.text('Test was run from string', 10, 10, { color = 'GREEN' })
                frame.display.show()
            else
                frame.display.clear()
                frame.display.text('Test was run from string', 10, 10, 0x00FF00)
            end

            frame.sleep(1)
        end
        """

        self.assertIsNone(await b.upload_file_from_string(lua_file, "test.lua"))

        self.assertIsNone(await b.send_lua("require('test')"))
        await asyncio.sleep(1)
        self.assertIsNone(await b.send_break_signal())
        self.assertEqual(await b.send_lua("frame.file.remove('test.lua');print(0)", await_print=True), "0")

        await b.disconnect()


if __name__ == "__main__":
    unittest.main()