import asyncio
from typing import Optional


def event_loop(attached: Optional[asyncio.AbstractEventLoop]) -> asyncio.AbstractEventLoop:
    """
    The event loop a receiver should hand its data to: the one captured in
    attach(), else the running loop (for a receiver wired up directly from the
    loop without attach()).

    Receivers queue data with call_soon_threadsafe() on this loop because the
    Halo emulator invokes data handlers from its Lua thread, where
    asyncio.create_task() has no running loop.
    """
    return attached if attached is not None else asyncio.get_running_loop()
