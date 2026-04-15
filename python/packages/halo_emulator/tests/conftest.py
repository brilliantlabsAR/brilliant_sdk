"""pytest fixtures for halo_emulator tests."""
from __future__ import annotations

import pytest
from pathlib import Path

from halo_emulator import HaloEmulator

LUA_DIR = Path(__file__).parent / "lua"


@pytest.fixture
def emulator(tmp_path: Path):
    """Fresh emulator with a temp sandbox; stopped and cleaned up after test."""
    emu = HaloEmulator(sandbox_dir=tmp_path, print_handler=None)
    yield emu
    if emu.is_running():
        emu.stop()
