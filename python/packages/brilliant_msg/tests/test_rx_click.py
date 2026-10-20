"""
Tests for RxClick: ClickType mapping, handler dispatch via BrilliantMsg,
and thread-safe queue delivery (the emulator invokes handlers from its Lua
thread, not the event loop thread).
"""
import asyncio
import threading

from brilliant_msg import BrilliantMsg, RxClick, ClickType


async def test_attach_returns_queue_and_registers():
    frame = BrilliantMsg()
    rx = RxClick()
    queue = await rx.attach(frame)

    assert isinstance(queue, asyncio.Queue)

    # dispatch through the BrilliantMsg data-response path
    await frame._handle_data_response(bytes([0x0B, 1]))
    assert await asyncio.wait_for(queue.get(), timeout=1) == ClickType.SINGLE

    await frame._handle_data_response(bytes([0x0B, 2]))
    assert await asyncio.wait_for(queue.get(), timeout=1) == ClickType.DOUBLE

    await frame._handle_data_response(bytes([0x0B, 3]))
    assert await asyncio.wait_for(queue.get(), timeout=1) == ClickType.LONG

    rx.detach(frame)
    assert rx.queue is None


async def test_unknown_and_short_messages_ignored():
    frame = BrilliantMsg()
    rx = RxClick()
    queue = await rx.attach(frame)

    rx.handle_data(bytes([0x0B]))        # too short
    rx.handle_data(bytes([0x0B, 99]))    # unknown click type
    await asyncio.sleep(0.05)
    assert queue.empty()

    rx.detach(frame)


async def test_handle_data_from_foreign_thread():
    """The emulator calls handlers from its Lua thread; delivery must still work."""
    frame = BrilliantMsg()
    rx = RxClick()
    queue = await rx.attach(frame)

    thread = threading.Thread(target=rx.handle_data, args=(bytes([0x0B, 1]),))
    thread.start()
    thread.join()

    assert await asyncio.wait_for(queue.get(), timeout=1) == ClickType.SINGLE
    rx.detach(frame)


async def test_unattached_handle_data_is_noop():
    rx = RxClick()
    rx.handle_data(bytes([0x0B, 1]))  # must not raise
