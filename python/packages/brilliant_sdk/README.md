# brilliant-sdk

Python SDK for [Brilliant Labs](https://brilliant.xyz/) Frame and Halo devices.

This is a meta-package that installs both `brilliant-ble` and `brilliant-msg` as dependencies, so you can get everything with a single install:

```bash
pip install brilliant-sdk
```

## Usage

```python
from brilliant_ble import BrilliantBle, BrilliantDeviceType
from brilliant_msg import BrilliantMsg, TxPlainText, TxSprite
```

Or import directly from the meta-package:

```python
from brilliant_sdk import BrilliantBle, BrilliantMsg, TxPlainText
```

## Packages

- **[brilliant-ble](../brilliant_ble/README.md)** — low-level Bluetooth LE connection library
- **[brilliant-msg](../brilliant_msg/README.md)** — message types and protocol handlers
