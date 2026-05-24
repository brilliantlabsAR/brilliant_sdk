# Brilliant SDK for Python

This is the monorepo for the **Brilliant SDK for Python**, supporting [Brilliant Labs](https://brilliant.xyz/) devices such as **Halo** and **Frame**.

It contains the following Python packages:

| Package | PyPI name | Description |
|---------|-----------|-------------|
| [`frame_ble`](./packages/frame_ble) | `frame-ble` | Low-level Bluetooth LE interface to Brilliant Labs devices |
| [`frame_msg`](./packages/frame_msg) | `frame-msg` | Application-level message types (sprites, text, audio, IMU, photos) |
| [`halo_emulator`](./packages/halo_emulator) | `halo-emulator` | Software emulator for the Halo Lua runtime — no hardware required (experimental) |

---

## 📦 Repository Structure

```text
python/
├── packages/
│   ├── frame_ble/        # BLE transport (bleak)
│   ├── frame_msg/        # Message types and protocol
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

This installs all three packages as editable installs, resolving `frame-ble` and `frame-msg` from the local workspace rather than PyPI.

---

## 🔧 Common Commands

| Command | Description |
|---------|-------------|
| `uv sync --all-packages` | Install all packages (editable) |
| `uv sync --all-packages --all-extras` | Include test and optional dependencies |
| `uv run pytest packages/frame_msg/tests/` | Run `frame_msg` tests |
| `uv run pytest packages/halo_emulator/tests/` | Run `halo_emulator` tests |
| `uv run pytest packages/frame_msg/tests/ packages/halo_emulator/tests/` | Run all software tests |
| `halo-emulator ./my_app/` | Launch interactive emulator REPL |

---

## 🧪 Testing

The `frame_msg` and `halo_emulator` packages have automated test suites that run without any hardware.

```bash
cd python

# Install all test dependencies
uv sync --all-packages --all-extras

# Run frame_msg tests (message packing/parsing, handler dispatch)
uv run pytest packages/frame_msg/tests/

# Run halo_emulator tests (Lua VM, display primitives, event injection)
uv run pytest packages/halo_emulator/tests/

# Run both together
uv run pytest packages/frame_msg/tests/ packages/halo_emulator/tests/
```

The `frame_ble` package has hardware integration tests that require a connected device over BLE:

```bash
# Requires a connected Frame or Halo device
uv run pytest packages/frame_ble/tests/test_ble.py
```

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

All packages are released under the [BSD 3-Clause License](./packages/frame_ble/LICENSE).
