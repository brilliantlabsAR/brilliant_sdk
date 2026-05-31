# Brilliant SDK for WebBluetooth (TypeScript)

This is the monorepo for the **Brilliant SDK for WebBluetooth**, supporting [Brilliant Labs](https://brilliant.xyz/) devices such as **Halo** and **Frame** from browser-based TypeScript/JavaScript applications.

It contains the following npm packages:

| Package | npm name | Description |
|---------|----------|-------------|
| [`brilliant-sdk`](./packages/brilliant-sdk) | `brilliant-sdk` | Meta-package — installs both `brilliant-ble` and `brilliant-msg` |
| [`brilliant-ble`](./packages/brilliant-ble) | `brilliant-ble` | Low-level WebBluetooth interface to Brilliant Labs devices |
| [`brilliant-msg`](./packages/brilliant-msg) | `brilliant-msg` | Application-level message types (sprites, text, audio, IMU, photos, clicks) |

---

## 📦 Repository Structure

```text
webbluetooth/
└── packages/
    ├── brilliant-sdk/    # Meta-package (installs brilliant-ble + brilliant-msg)
    ├── brilliant-ble/    # WebBluetooth transport layer
    │   ├── src/
    │   ├── vite.config.ts
    │   └── package.json
    └── brilliant-msg/    # Message types and protocol
        ├── src/
        │   ├── tx/       # Host → device message types
        │   ├── rx/       # Device → host message types
        │   └── lua/      # Bundled Lua libraries (uploaded to device)
        ├── vite.config.ts
        └── package.json
```

---

## 🚀 Getting Started (for Developers)

### 1. Clone the repo

```bash
git clone https://github.com/brilliantlabsAR/brilliant_sdk.git
cd brilliant_sdk/webbluetooth
```

### 2. Install dependencies

Each package manages its own dependencies. Install them separately:

```bash
cd packages/brilliant-ble && npm install
cd ../brilliant-msg && npm install
```

### 3. Build the packages

```bash
# Build the BLE transport first (brilliant-msg depends on it)
cd packages/brilliant-ble && npm run build

# Then build the message layer
cd ../brilliant-msg && npm run build
```

---

## 🔧 Common Commands

Run from inside each package directory:

| Command | Description |
|---------|-------------|
| `npm run build` | Build the library (`dist/`) |
| `npm run dev` | Start Vite dev server for the example app |
| `npm run dev:demo` | Start the demo/example app |
| `npm run docs:api` | Generate TypeDoc API documentation |

---

## 📦 Publishing

Each package is published independently to npm.

```bash
cd packages/<package-name>
npm run build
npm publish
```

Make sure any local `file:` dependencies are replaced with proper semver version constraints before publishing.

---

## ⚠️ Browser Compatibility

WebBluetooth is only available in Chromium-based browsers (Chrome, Edge, Opera) on desktop and Android. It is **not** available in Firefox or Safari.

---

## 📝 Contributing

Contributions are welcome! If you're building features or fixing bugs, please open a pull request targeting the `main` branch.

---

## 📄 License

All packages are released under the [BSD 3-Clause License](./packages/brilliant-ble/LICENSE).
