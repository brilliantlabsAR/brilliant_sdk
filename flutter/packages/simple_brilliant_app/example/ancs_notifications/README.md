# Halo ANCS (iOS Notifications) Demo

Shows the phone's notifications on the Halo display and mirrors them in the
app, using the Halo firmware's **ANCS client** (`frame.ancs` Lua API,
firmware >= 0.8.6).

ANCS (Apple Notification Center Service) is a GATT service published by iOS:
the phone is the server and the Halo is the client. Because this app runs
natively on the iPhone that the Halo connects to, a real ANCS server is
available on the link - no re-pairing with another host is needed.

## How it works

1. **Connect / Start** uploads `assets/frame_app.lua` to the Halo and runs it.
2. Pressing the **play** button sends `START_ANCS_MSG`; the frameside app
   registers `frame.ancs.notification_callback(...)`, which subscribes to
   ANCS. iOS immediately replays every notification currently in Notification
   Center (`pre_existing = true`) followed by live events.
3. For each notification the frameside app fetches title/message/app id via
   `frame.ancs.get_notification_attributes(uid, ...)`, renders the newest
   ones on the Halo display, and forwards compact event records to this app
   (message flag `0x0B`).
4. The **stop** button unsubscribes (`frame.ancs.notification_callback(nil)`).

## Requirements

- Halo firmware with the `frame.ancs` API
- The Halo must be **bonded** to the phone: ANCS requires an encrypted link.
  iOS asks for permission to share notifications during pairing (or via the
  device's entry in Settings > Bluetooth > "Share System Notifications").
- ANCS is iOS-only: on Android this app still runs, but the Halo will report
  ANCS as unavailable.

## See also

- `applications/halo/protocol.md` section 7.13 in the firmware repo for the
  full `frame.ancs` Lua API
- `python/packages/brilliant_ble/examples/halo_ancs_notifications.py` for a
  standalone variant that installs a persistent `main.lua` so the Halo shows
  notifications without any companion app running
