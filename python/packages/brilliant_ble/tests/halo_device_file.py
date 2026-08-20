"""Helpers for tests that have to install their own main.lua.

Several tests need main.lua to be theirs: the reset path re-runs whatever is
present, so that is the only way to get a script executing at boot. Doing it
naively destroys whatever application the device has installed -- and on a real
device that is the user's app, gone.

`preserve_main_lua()` reads the existing file, hands control back, and puts it
back afterwards even if the body raised.

No PEP 723 header: this is imported by the test scripts, which each declare
brilliant-ble themselves, and `uv run <script>` puts the script's directory on
sys.path so a plain `import halo_device_file` resolves.
"""

import asyncio
from contextlib import asynccontextmanager

_CHUNK = 120


class _Fenced:
    """Fenced request/reply over the Lua REPL.

    await_print returns only the first notification of a reply and stops
    listening, so a longer reply bleeds into the next command's answer. Fencing
    each reply between unique markers and waiting for the fence drains the whole
    thing, and ignores whatever a running main.lua prints in the meantime.
    """

    def __init__(self, ble):
        self.b = ble
        self.rx = []
        self.n = 0

    async def probe(self, body, timeout=8, raw=False):
        self.n += 1
        start, end = f"<<S{self.n}>>", f"<<E{self.n}>>"
        previous = self.b._user_print_response_handler
        self.b._user_print_response_handler = self.rx.append
        self.rx.clear()
        try:
            await self.b.send_lua(
                f"local ok, v = pcall(function() {body} end) "
                f"print('{start}' .. (ok and 'OK\\t' or 'ERR\\t') .. tostring(v) .. '{end}')"
            )
            loop = asyncio.get_running_loop()
            deadline = loop.time() + timeout
            while loop.time() < deadline:
                joined = "".join(self.rx)
                if start in joined and end in joined:
                    reply = joined.split(start)[1].split(end)[0]
                    status, _, value = reply.partition("\t")
                    # raw keeps whitespace at chunk boundaries; stripping it
                    # silently corrupts anything read back byte for byte.
                    return status == "OK", value if raw else value.strip()
                await asyncio.sleep(0.05)
            raise Exception(f"device didn't respond to: {body}")
        finally:
            self.b._user_print_response_handler = previous


async def read_device_file(ble, path):
    """Return the file's contents byte for byte, or None if it does not exist."""
    f = _Fenced(ble)
    ok, _ = await f.probe(f"_bf = frame.file.open('{path}', 'r')")
    if not ok:
        return None
    data = ""
    try:
        while True:
            # The 'D' prefix distinguishes a chunk from the EOF marker without
            # relying on the chunk being non-empty.
            ok, chunk = await f.probe(
                f"local c = _bf:read({_CHUNK}) return c and ('D' .. c) or 'EOF'",
                raw=True,
            )
            if not ok or chunk == "EOF":
                break
            data += chunk[1:]
    finally:
        await f.probe("_bf:close() _bf = nil")
    return data


@asynccontextmanager
async def preserve_main_lua(ble, verbose=True):
    """Save the device's main.lua and restore it on the way out.

    Cleanup uses send_remove_signal(), which deletes main.lua and restarts the
    VM in firmware, so it still works when the installed script has wedged the
    REPL. Restoring happens even if the body raised.
    """
    saved = await read_device_file(ble, "main.lua")
    if verbose:
        size = "none" if saved is None else f"{len(saved)} bytes"
        print(f"saved existing main.lua ({size}) for restore")
    try:
        yield saved
    finally:
        await ble.send_remove_signal()
        await asyncio.sleep(1)
        if saved is not None:
            await ble.upload_file_from_string(saved, "main.lua")
            await ble.send_reset_signal()
            if verbose:
                print(f"restored original main.lua ({len(saved)} bytes)")
