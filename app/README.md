# nearby for Linux

A Flutter desktop app that watches for Bluetooth devices around this computer, keeps a whitelist, and pings and notifies you when an unlisted device comes into range.

## How it works

- **Scanning.** The app runs BlueZ discovery over the system D-Bus. No root is needed, but `bluetoothd` must be running and the adapter powered on. It sets `DuplicateData` and a permissive `RSSI` filter, so BlueZ reports RSSI for every advertisement rather than only on changes of 8 dB or more. Bluetooth LE is on by default; Settings can add Classic inquiry.
- **Distance.** Each device's RSSI is smoothed with a Kalman filter, then converted to metres with the log-distance path-loss model. The 1 m reference comes from a per-device calibration if there is one, then from the device's advertised TX power, then from a default. This is the same model as the web app. Expect a few metres of error indoors.
- **Learning.** On first launch, as soon as scanning starts, the app learns for 2 minutes and whitelists every device it sees whose address is stable. Until one learning session has finished, every launch learns again. **Learn** repeats this at any time. You can also tick devices in the list, or use **Whitelist all in range**.
- **Alerts.** An *arrival* is an unlisted device heard at least twice after being away for the out-of-range time (1 minute by default). Each arrival plays `device-added.oga` from the freedesktop sound theme, trying `pw-play`, then `paplay`, then `canberra-gtk-play`. It also shows a desktop notification with a **Whitelist** button.
  - Arrivals within about 1.5 s share one alert, and alerts are at least 10 s apart.
  - A device that has alerted stays quiet for 30 minutes, even if it leaves and returns.
  - You can limit alerts to devices within a radius.
- **Rotating addresses.** Phones, watches and earbuds advertise from a private address that changes about every 15 minutes, so they can't be whitelisted. They appear in the list as *rotating*, and alerting on them is off by default. A paired device shows up under its fixed identity address instead.
- **Scan duty cycle.** If a connected headset stutters or drops while the app scans, turn on **Rest between scans** in Settings.

Settings, the whitelist and the learning state are stored as JSON in `~/.local/share/io.github.fingerskier.nearby/`. They are saved shortly after each change, and again when you close the window or the app gets SIGINT or SIGTERM. Only one copy of the app runs at a time; launching it again brings up the existing window.

## Build and run

You need Flutter 3.47 or newer and the Linux desktop toolchain (`clang`, `cmake`, `ninja`, GTK 3 headers).

```sh
cd app
flutter pub get
flutter run -d linux             # debug
flutter test
flutter build linux --release    # build/linux/x64/release/bundle/nearby
linux/packaging/install.sh       # installs to ~/.local/lib/nearby with a launcher entry
```

CI builds the same bundle, with `packaging/install.sh` inside, as the `nearby-linux-x64` artifact of the *Linux app* workflow.

To check an adapter from the terminal without the UI:

```sh
dart run tool/scan.dart 15    # scan for 15 s and list what was heard, nearest first
```
