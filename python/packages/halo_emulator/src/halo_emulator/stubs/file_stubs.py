"""frame.file.* stubs — sandboxed OS file operations."""
from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any


class LuaFileHandle:
    """Wraps a Python file object with Lua-style :read()/:write()/:close() methods."""

    def __init__(self, fobj: Any) -> None:
        self._f = fobj

    def read(self) -> str | None:
        line = self._f.readline()
        return line if line else None

    def write(self, data: str) -> None:
        self._f.write(str(data))

    def close(self) -> None:
        self._f.close()


class FileStub:
    def __init__(self, sandbox_dir: Path) -> None:
        self._root = sandbox_dir.resolve()

    def _safe(self, name: str) -> Path:
        p = (self._root / name).resolve()
        if not str(p).startswith(str(self._root)):
            raise PermissionError(f"Path escape: {name!r}")
        return p

    def open(self, name: str, mode: str = "r") -> LuaFileHandle:
        p = self._safe(name)
        p.parent.mkdir(parents=True, exist_ok=True)
        return LuaFileHandle(p.open(mode, encoding="latin-1"))

    def remove(self, name: str) -> None:
        p = self._safe(name)
        if p.is_dir():
            p.rmdir()
        else:
            p.unlink()

    def remove_all(self) -> None:
        for item in self._root.iterdir():
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()

    def rename(self, old: str, new: str) -> None:
        self._safe(old).rename(self._safe(new))

    def listdir(self, path: str = "") -> list[str]:
        p = self._safe(path) if path else self._root
        return [item.name for item in p.iterdir()]

    def mkdir(self, path: str) -> None:
        self._safe(path).mkdir(parents=True, exist_ok=True)
