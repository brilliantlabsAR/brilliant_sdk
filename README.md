# Brilliant SDK for Flutter

This is the monorepo for the **Brilliant SDK for Flutter**, supporting [Brilliant Labs](https://brilliant.xyz) devices such as **Halo** and **Frame**.

It contains the following Flutter packages:

| Package | Description |
|--------|-------------|
| [`brilliant_sdk`](./packages/brilliant_sdk) | Meta-package for consuming the SDK in apps |
| [`frame_ble`](./packages/frame_ble) | Bluetooth Low Energy interface to Brilliant Labs devices |
| [`frame_msg`](./packages/frame_msg) | Message format and protocol definitions for Frame devices |

---

## 📦 Repository Structure

```text
brilliant_sdk_flutter/
├── packages/
│   ├── brilliant_sdk/ # Meta-package
│   ├── frame_ble/     # BLE communication logic
│   └── frame_msg/     # Message and protocol formats
├── melos.yaml         # Melos workspace configuration
└── pubspec.yaml       # Root pubspec (for tooling only)
```

---

## 🚀 Getting Started (for Developers)

### 1. Clone the repo

```bash
git clone https://github.com/brilliantlabsAR/brilliant_sdk_flutter.git
cd brilliant_sdk_flutter
```

### 2. Install Melos

```bash
dart pub global activate melos
```

Make sure your $PATH includes the Dart pub cache:

```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

### 3. Bootstrap the workspace

This will run `flutter pub get` in all packages and link local dependencies:

```bash
melos bootstrap
```

## 🔧 Common Commands

| Command           | Description                           |
| ----------------- | ------------------------------------- |
| `melos bootstrap` | Get dependencies for all packages     |
| `melos analyze`   | Run `flutter analyze` in all packages |
| `melos format`    | Format all Dart files                 |
| `melos test`      | Run tests in all packages             |
| `melos version`   | Bump versions across packages         |

## 📦 Publishing

To publish a package to pub.dev:

Run `melos version` to bump versions.

Run `dart pub publish` from the package folder.

Make sure you replace all `path:` dependencies with proper version constraints before publishing!

## 🧪 Testing

You can run all tests across the SDK with:
```bash
melos test
```

Or run tests for a specific package:
```bash
cd packages/frame_ble
flutter test
```

## 📝 Contributing
Contributions are welcome! If you're building features or fixing bugs, please open a pull request targeting the `main` branch.

## 🧠 Future Plans
* Rename `frame_ble` → `brilliant_ble`
* Rename `frame_msg` → `brilliant_msg`

## 📄 License
* [BSD 3-Clause "New" or "Revised"](/LICENSE)