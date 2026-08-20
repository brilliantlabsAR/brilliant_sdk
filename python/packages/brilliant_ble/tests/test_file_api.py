"""
Tests the Halo file Lua library over Bluetooth.
"""

import asyncio, sys
from brilliant_ble import BrilliantBle
import argparse


# Runs once at startup: looks an entry up by name so assertions do not depend on
# directory ordering or on how many unrelated files happen to be on the device.
# Single line on purpose: the REPL treats a newline as end-of-command, so a
# multi-line definition arrives truncated.
LUA_HELPERS = (
    "function _find(dir, name) "
    "for _, e in ipairs(frame.file.listdir(dir)) do "
    "if e['name'] == name then return e end end return nil end"
)


class TestBluetooth(BrilliantBle):
    def __init__(self):
        super().__init__()
        self._passed_tests = 0
        self._failed_tests = 0
        self._seq = 0
        self._rx = []
        self._rx_event = asyncio.Event()

    def _on_print(self, text):
        self._rx.append(text)
        self._rx_event.set()

    def _log_passed(self, sent, responded):
        self._passed_tests += 1
        if responded == None:
            print(f"\033[92mPassed: {sent}")
        else:
            print(f"\033[92mPassed: {sent} => {responded}")

    def _log_failed(self, sent, responded, expected):
        self._failed_tests += 1
        if expected == None:
            print(f"\033[91mFAILED: {sent} => {responded}")
        else:
            print(f"\033[91mFAILED: {sent} => {responded} != {expected}")

    async def _probe(self, body: str, timeout=5):
        """Run `body` in a pcall and return (ok, value) once the reply is complete.

        `await_print` hands back only the FIRST notification of a reply and
        stops listening. Continuation packets of a longer reply -- a multi-line
        Lua error, say -- therefore arrive while the NEXT command is already
        awaiting, and get returned as that command's answer, shifting every
        result from the first long message onward.

        So each command instead ends by printing a unique sentinel, and this
        waits for that sentinel rather than for "some notification": everything
        the command emitted has necessarily arrived by then, and nothing can be
        left over to be misread as the next command's reply.

        The pcall keeps the sentinel reachable even when `body` raises, and
        collapses the reply to a single `OK<tab>value` / `ERR<tab>message` line
        so a failure is reported rather than becoming a timeout.

        The reply is fenced on both sides, not just terminated: anything the
        device happens to emit on its own (a still-running main.lua, a late log
        line) would otherwise be read as part of the answer.
        """
        self._seq += 1
        start = f"<<S{self._seq}>>"
        end = f"<<E{self._seq}>>"
        self._rx.clear()
        self._rx_event.clear()

        await self.send_lua(
            f"local ok, v = pcall(function() {body} end) "
            f"print('{start}' .. (ok and 'OK\\t' or 'ERR\\t') .. tostring(v) .. '{end}')"
        )

        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while True:
            joined = "".join(self._rx)
            if start in joined and end in joined:
                reply = joined.split(start)[1].split(end)[0]
                status, _, value = reply.partition("\t")
                return status == "OK", value.strip()
            remaining = deadline - loop.time()
            if remaining <= 0:
                raise Exception(f"device didn't respond to: {body}")
            self._rx_event.clear()
            try:
                await asyncio.wait_for(self._rx_event.wait(), timeout=remaining)
            except asyncio.TimeoutError:
                pass

    async def value(self, expr: str):
        """Evaluate a Lua expression and return its value as a string."""
        ok, value = await self._probe(f"return {expr}")
        if not ok:
            raise Exception(f"error evaluating {expr}: {value}")
        return value

    async def initialize(self, name=None):
        name = await self.connect(name=name, print_response_handler=self._on_print)
        # The device boots into main.lua; break it so the REPL answers and so
        # its output cannot interleave with the replies below.
        await self.send_break_signal()
        fw = await self.value("frame.FIRMWARE_VERSION")
        tag = await self.value("frame.GIT_TAG")
        batt = await self.value("frame.battery_level()")
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")
        await self._probe(LUA_HELPERS)

    async def end(self):
        passed_tests = self._passed_tests
        total_tests = self._passed_tests + self._failed_tests
        print("\033[0m")
        print(f"Done! Passed {passed_tests} of {total_tests} tests")
        # Restart the Lua VM so the device resumes running main.lua.
        await self.send_reset_signal()
        await self.disconnect()
        return self._failed_tests

    async def lua_equals(self, send: str, expect):
        ok, response = await self._probe(f"return {send}")
        if ok and response == str(expect):
            self._log_passed(send, response)
        else:
            self._log_failed(send, response, expect)

    async def lua_is_type(self, send: str, expect):
        ok, response = await self._probe(f"return type({send})")
        if ok and response == str(expect):
            self._log_passed(send, response)
        else:
            self._log_failed(send, response, expect)

    async def lua_has_length(self, send: str, length: int):
        ok, response = await self._probe(f"return {send}")
        if ok and len(response) == length:
            self._log_passed(send, response)
        else:
            self._log_failed(send, f"len({len(response)})", f"len({length})")

    async def lua_send(self, send: str):
        ok, response = await self._probe(send)
        if ok:
            self._log_passed(send, None)
        else:
            self._log_failed(send, response, None)

    async def lua_error(self, send: str):
        ok, response = await self._probe(send)
        if not ok:
            self._log_passed(send, response.partition(":1: ")[2] or response)
        else:
            self._log_failed(send, "no error", "an error")

    async def data_equal(self, send: bytearray, expect: bytearray):
        response = await self.send_data(send, await_data=True)
        if response == expect:
            self._log_passed(send, response)
        else:
            self._log_failed(send, response, expect)


async def main():
    parser = argparse.ArgumentParser(
        description="Connect to a Halo/Frame device over BLE and run this test."
    )
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()

    test = TestBluetooth()
    await test.initialize(args.name)

    # Entry count before this test adds anything. Asserting on deltas rather
    # than on absolute counts keeps the test valid on a device that already
    # holds recordings from the microphone or AEC harnesses.
    base = int(await test.value("#frame.file.listdir('/')"))

    ## Test all modes (writable, read only, and append)
    await test.lua_send("f=frame.file.open('test.lua', 'w')")
    await test.lua_send("f:write('test 123')")
    await test.lua_send("f:close()")

    await test.lua_send("f=frame.file.open('test.lua', 'a')")
    await test.lua_send("f:write('\\n456')")
    await test.lua_send("f:close()")

    await test.lua_send("f=frame.file.open('test.lua', 'r')")
    await test.lua_error("f:write('789')")
    await test.lua_equals("f:read()", "test 123")
    await test.lua_equals("f:read()", "456")
    await test.lua_equals("f:read()", "nil")
    await test.lua_send("f:close()")

    # Reopening a file in write mode should erase the file
    await test.lua_send("f=frame.file.open('test.lua', 'w')")
    await test.lua_send("f:write('test 789')")
    await test.lua_send("f:close()")

    await test.lua_send("f=frame.file.open('test.lua', 'r')")
    await test.lua_equals("f:read()", "test 789")
    await test.lua_send("f:close()")

    ## Prevent operations when file is closed
    await test.lua_error("f:read()")
    await test.lua_error("f:write('000')")
    # Halo: closing an already-closed file is a no-op, not an error
    # (lua_file.c:176 - close() doubles as the __gc/__close metamethod)
    await test.lua_send("f:close()")

    ## List, rename and delete file
    await test.lua_equals("#frame.file.listdir('/')", base + 1)
    await test.lua_equals("_find('/', 'test.lua')['size']", "8")
    await test.lua_equals("_find('/', 'test.lua')['type']", "1")
    await test.lua_send("frame.file.rename('test.lua', 'test2.lua')")
    await test.lua_equals("_find('/', 'test2.lua')['name']", "test2.lua")
    await test.lua_equals("_find('/', 'test.lua')", "nil")
    await test.lua_send("frame.file.remove('test2.lua')")
    await test.lua_equals("#frame.file.listdir('/')", base)

    ## Create and delete directories
    await test.lua_send("frame.file.mkdir('/this/is/some/path')")

    await test.lua_equals("#frame.file.listdir('/')", base + 1)
    await test.lua_equals("_find('/', 'this')['name']", "this")
    await test.lua_equals("_find('/', 'this')['type']", "2")

    await test.lua_send("frame.file.listdir('/this')")
    await test.lua_send("frame.file.listdir('/this/is')")
    await test.lua_error("frame.file.listdir('/this/is/not')")

    await test.lua_send("frame.file.remove('/this/is/some/path')")
    await test.lua_send("frame.file.remove('/this/is/some')")
    await test.lua_send("frame.file.remove('/this/is')")
    await test.lua_send("frame.file.remove('/this')")
    await test.lua_equals("#frame.file.listdir('/')", base)

    return await test.end()


sys.exit(asyncio.run(main()))
