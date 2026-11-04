# Brilliant SDK for Python

This is the monorepo for the **Brilliant SDK for Python**, supporting [Brilliant Labs](https://brilliant.xyz/) devices such as **Halo** and **Frame**.

It contains the following Python packages:

| Package | PyPI name | Description |
|---------|-----------|-------------|
| [`brilliant_sdk`](./packages/brilliant_sdk) | `brilliant-sdk` | Meta-package: installs `brilliant-ble` + `brilliant-msg` together |
| [`brilliant_ble`](./packages/brilliant_ble) | `brilliant-ble` | Low-level Bluetooth LE interface to Brilliant Labs devices |
| [`brilliant_msg`](./packages/brilliant_msg) | `brilliant-msg` | Application-level message types (sprites, text, audio, IMU, photos) |
| [`halo_emulator`](./packages/halo_emulator) | `halo-emulator` | Software emulator for the Halo Lua runtime — no hardware required (experimental) |

---

## 📦 Repository Structure

```text
python/
├── packages/
│   ├── brilliant_sdk/    # Meta-package (depends on brilliant-ble + brilliant-msg)
│   ├── brilliant_ble/    # BLE transport (bleak)
│   ├── brilliant_msg/    # Message types and protocol
│   └── halo_emulator/    # Halo Lua runtime emulator
├── pyproject.toml        # uv workspace configuration
└── uv.lock
```

---

## 🚀 Getting Started (for Developers)

### 1. Install uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 2. Clone the repo and sync the workspace

```bash
git clone https://github.com/brilliantlabsAR/brilliant_sdk.git
cd brilliant_sdk/python
uv sync --all-packages
```

This installs all packages as editable installs, resolving `brilliant-ble` and `brilliant-msg` from the local workspace rather than PyPI.

---

## 🔧 Common Commands

| Command | Description |
|---------|-------------|
| `uv sync --all-packages` | Install all packages (editable) |
| `uv sync --all-packages --all-extras` | Include test and optional dependencies |
| `uv run pytest` | Run all hardware-free tests |
| `uv run pytest packages/brilliant_msg/tests/` | Run `brilliant_msg` tests |
| `uv run pytest packages/halo_emulator/tests/` | Run `halo_emulator` tests |
| `halo-emulator ./my_app/` | Launch interactive emulator REPL |

---

## 🧪 Testing

A bare `pytest` run is hardware-free: it covers `brilliant_msg` (message
packing/parsing, handler dispatch), `halo_emulator` (Lua VM, display
primitives, event injection) and the `brilliant_ble` unit tests, while
device-requiring tests are skipped automatically.

```bash
cd python

# Install all test dependencies
uv sync --all-packages --all-extras

# Run everything that works without a device
uv run pytest
```

Tests and scripts that need a real Frame or Halo connected over BLE:

```bash
# Opt in to the hardware integration tests (marked `device`)
BRILLIANT_DEVICE=1 uv run pytest packages/brilliant_ble/tests/test_ble.py

# Most other test_*.py files under brilliant_ble/tests/ are standalone
# device-exercise scripts, run directly rather than through pytest:
uv run python packages/brilliant_ble/tests/test_camera.py --name Halo
```

To run every unattended device check in one go (the standalone scripts that
end on their own, the bounded polling ones, and the pytest device modules):

```bash
python3 tools/run_device_tests.py --name "Halo AB"
```

It prints PASS/FAIL per script, keeps each script's output under
`./device-test-logs`, and exits non-zero if anything failed. The Halo
firmware's pre-release battery runs it against each release candidate.

---

## 📦 Publishing

Each package is published independently to PyPI.

```bash
cd packages/<package_name>
uv build
uv publish
```

Make sure local `path:` or workspace sources have been replaced with proper version constraints before publishing.

---

## 📝 Contributing

Contributions are welcome! If you're building features or fixing bugs, please open a pull request targeting the `main` branch.

---

## 📄 License

All packages are released under the [BSD 3-Clause License](./packages/brilliant_ble/LICENSE).
