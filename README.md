# APC UPS Monitor

A tiny native macOS menu-bar monitor for the APC Back-UPS ES 600M1.

## Design goals

- Keep macOS `ioupsd` in charge of the UPS.
- Do **not** run `apcupsd` or NUT.
- Open the USB HID device with `kIOHIDOptionsTypeNone` only (shared, non-exclusive).
- Never send control commands to the UPS.
- Read battery/status from Apple's `IOPowerSources` API.
- Read HID Power Device `PercentLoad` (usage page `0x84`, usage `0x35`) when available.
- Estimate watts as `330 W × load %` for the BE600M1.

## Run & Install

- **Option A (Command line build & install)**:
  ```bash
  # Build only (generates APCUPSMonitor.app locally)
  ./build.sh

  # Build and install to /Applications
  ./build.sh install
  ```
- **Option B (Xcode)**:
  Open `APCUPSMonitor.xcodeproj` in Xcode and Run.

The app has `LSUIElement = true`, so it appears only in the menu bar.

## Important safety check

After launching the app, verify that macOS still shows its native UPS entry and battery percentage in the menu bar / Energy settings. This app intentionally never uses `kIOHIDOptionsTypeSeizeDevice`.

If `Load` is shown as `—`, open **Diagnostics → HID** and inspect the raw usage/value list. The BE600M1 has APC-specific usages in addition to standard Power Device usages, and we can map those after seeing the live values.

## 0.1.2 — refresh recovery & version display

- Native macOS and HID reads run independently in short-lived reader processes.
  Each read recreates the IOKit connection; a 5-second deadline kills a stuck
  reader without blocking the menu or the other data source.
- Native data polls every 2 seconds. Successful HID reads have a minimum 2-second
  interval; unavailable HID backs off for 30 seconds. Refresh bypasses backoff,
  but never starts a second reader while the previous one is running/reaping.
- Polling uses common run-loop modes, including menu tracking. Sleep cancels
  readers and invalidates displayed values; wake resumes polling automatically.
- Failed reads clear old values. The menu and Diagnostics → Health show read
  status/times. These times confirm API reads, not the UPS firmware's own update
  time; macOS can still return cached values.
- All HID access remains shared and read-only. No changes to ioupsd or macOS UPS
  shutdown settings are needed.

Run fault/recovery regression tests with `./Tests/run.sh`. The test executable
simulates hung, missing and malformed readers without touching the real UPS.

For direct read-only diagnosis (JSON output, no menu UI):

```bash
./APCUPSMonitor.app/Contents/MacOS/APCUPSMonitor --read-system
./APCUPSMonitor.app/Contents/MacOS/APCUPSMonitor --read-hid
```

The CLI modes are single synchronous reads; when called manually, they do not
have the parent app's 5-second watchdog.

## License

This project is licensed under the [MIT License](LICENSE).

