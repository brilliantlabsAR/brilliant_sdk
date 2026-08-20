"""
Tests that a Lua file on the device is executed, both via require() and via a
Ctrl-D reset.

This test necessarily installs its own main.lua, because the reset path re-runs
whatever main.lua is present. It therefore saves the device's existing main.lua
first and restores it afterwards, and does its cleanup in a finally block so an
interrupted run cannot leave an infinite-loop main.lua running at every boot.
"""

import asyncio, sys
from brilliant_ble import BrilliantBle
from halo_device_file import preserve_main_lua
import argparse


# Deliberately an infinite loop: the point is to prove the file keeps running
# until it is broken out of.
LOOP_MAIN = "while true do\n" "print('test')\n" "frame.sleep(1)\n" "end\n"


class TestBluetooth(BrilliantBle):
    def __init__(self):
        super().__init__()
        self._passed_tests = 0
        self._failed_tests = 0
        self._seq = 0
        self._rx = []

    def _on_print(self, text):
        self._rx.append(text)

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

    async def _probe(self, body: str, timeout=8):
        """Run `body` and return (ok, value), fencing the reply on both sides.

        Same reasoning as test_file_api.py: await_print returns only the first
        notification of a reply, so a longer message bleeds into the next
        command's answer. Waiting for a per-command fence drains the whole
        reply, and ignores anything main.lua prints in the meantime -- which
        matters here, where main.lua is a print loop by construction.
        """
        self._seq += 1
        start, end = f"<<S{self._seq}>>", f"<<E{self._seq}>>"
        self._rx.clear()
        await self.send_lua(
            f"local ok, v = pcall(function() {body} end) "
            f"print('{start}' .. (ok and 'OK\\t' or 'ERR\\t') .. tostring(v) .. '{end}')"
        )
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while loop.time() < deadline:
            joined = "".join(self._rx)
            if start in joined and end in joined:
                reply = joined.split(start)[1].split(end)[0]
                status, _, value = reply.partition("\t")
                return status == "OK", value.strip()
            await asyncio.sleep(0.05)
        raise Exception(f"device didn't respond to: {body}")

    async def initialize(self, name=None):
        name = await self.connect(name=name, print_response_handler=self._on_print)
        await self.send_break_signal()
        ok, fw = await self._probe("return frame.FIRMWARE_VERSION")
        ok, tag = await self._probe("return frame.GIT_TAG")
        ok, batt = await self._probe("return frame.battery_level()")
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    async def end(self):
        passed_tests = self._passed_tests
        total_tests = self._passed_tests + self._failed_tests
        print("\033[0m")
        print(f"Done! Passed {passed_tests} of {total_tests} tests")
        await self.disconnect()
        return self._failed_tests

    async def expect_prints(self, token: str, seconds: float, at_least: int):
        """Collect device output and assert `token` appears often enough.

        The loop under test prints on its own schedule, so this watches the
        stream rather than requesting a value -- which is also why the old
        `require('main') == 'test'` assertion was meaningless: require() never
        returns for an infinite loop, so the 'test' it compared against came
        from the loop's own output, not from require().
        """
        self._rx.clear()
        await asyncio.sleep(seconds)
        seen = "".join(self._rx).count(token)
        label = f"{token!r} printed >= {at_least}x in {seconds}s"
        if seen >= at_least:
            self._log_passed(label, f"{seen}x")
        else:
            self._log_failed(label, f"{seen}x", f">= {at_least}x")
        return seen

    async def expect_silence(self, token: str, seconds: float):
        """Assert the device stops printing `token` (i.e. the loop was broken)."""
        self._rx.clear()
        await asyncio.sleep(seconds)
        seen = "".join(self._rx).count(token)
        label = f"{token!r} stopped after break"
        if seen == 0:
            self._log_passed(label, "silent")
        else:
            self._log_failed(label, f"{seen}x", "0x")


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

    # The reset path re-runs whatever main.lua is on the device, so this test
    # has to install its own. Keep the original to put back.
    async with preserve_main_lua(test):
        await test.upload_file_from_string(LOOP_MAIN, "main.lua")

        ## Run it with require() and break execution after some time.
        ## The runtime already require()s 'main' at boot and require() memoises
        ## in package.loaded, so requiring it again would return the cached
        ## value and never execute the file just uploaded. Clear the entry
        ## first -- the same escape hatch a user needs after re-uploading a
        ## module mid-session.
        await test.send_lua("package.loaded['main'] = nil require('main')")
        await test.expect_prints("test", seconds=3, at_least=2)
        await test.send_break_signal()
        await test.expect_silence("test", seconds=3)

        ## Run it from a Ctrl-D reset and break execution after some time
        await test.send_reset_signal()
        await test.expect_prints("test", seconds=3, at_least=2)
        await test.send_break_signal()
        await test.expect_silence("test", seconds=3)
    return await test.end()


sys.exit(asyncio.run(main()))
