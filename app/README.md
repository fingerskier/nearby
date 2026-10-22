# nearby for Linux and Android

A Flutter app that watches for Bluetooth devices around this computer or phone, keeps a whitelist, and pings and notifies you when an unlisted device comes into range.

## How it works

- **Distance.** Each device's RSSI is smoothed with a Kalman filter, then converted to metres with the log-distance path-loss model. The 1 m reference comes from a per-device calibration if there is one, then from the device's advertised TX power, then from a default. This is the same model as the web app. Expect a few metres of error indoors.
- **Learning.** On first launch, as soon as scanning starts, the app learns for 2 minutes and whitelists every device it sees whose address is stable. Until one learning session has finished, every launch learns again. **Learn** repeats this at any time. You can also tick devices in the list, or use **Whitelist all in range**.
- **Alerts.** An *arrival* is an unlisted device heard at least twice after being away for the out-of-range time (1 minute by default). Each arrival plays a sound and shows a notification with a **Whitelist** button.
  - Arrivals within about 1.5 s share one alert, and alerts are at least 10 s apart.
  - A device that has alerted stays quiet for 30 minutes, even if it leaves and returns.
  - You can limit alerts to devices within a radius.
- **Rotating addresses.** Phones, watches and earbuds advertise from a private address that changes about every 15 minutes, so they can't be whitelisted. They appear in the list as *rotating*, and alerting on them is off by default.

## Linux

- **Scanning.** The app runs BlueZ discovery over the system D-Bus. No root is needed, but `bluetoothd` must be running and the adapter powered on. It sets `DuplicateData` and a permissive `RSSI` filter, so BlueZ reports RSSI for every advertisement rather than only on changes of 8 dB or more. Bluetooth LE is on by default; Settings can add Classic inquiry.
- **Alerts.** The sound is `device-added.oga` from the freedesktop sound theme, played with `pw-play`, then `paplay`, then `canberra-gtk-play`. Notifications go to the desktop's notification server.
- **Addresses.** BlueZ says whether an address is public or random. A paired device shows up under its fixed identity address instead of its rotating one.
- **Scan duty cycle.** If a connected headset stutters or drops while the app scans, turn on **Rest between scans** in Settings.
- **Data.** Settings, the whitelist and the learning state are stored as JSON in `~/.local/share/io.github.fingerskier.nearby/`. They are saved shortly after each change, and again when you close the window or the app gets SIGINT or SIGTERM. Only one copy of the app runs at a time; launching it again brings up the existing window.

## Android

Android 12 or newer, with Bluetooth LE.

- **Permissions.** The app asks for *Nearby devices* (Bluetooth scanning) and for notifications. It declares that it never uses scan results to find your location, so it needs neither location access nor Location turned on. In return, Android hides iBeacon and Eddystone beacons from it. If you decline twice, Android stops asking; **Allow** on the banner then opens the app's settings page.
- **In the background.** While nearby runs, a foreground service keeps it alive, with an ongoing notification that says what it is doing. It keeps guarding after you leave the app or swipe it away. **Stop** on that notification quits it.
- **Screen off.** Android pauses unfiltered Bluetooth scans while the screen is off. Then nearby switches to a filtered scan that still hears the common advertisers: devices that list any service UUID, devices from Apple, Samsung, Google, Microsoft, Garmin, Huawei, Xiaomi, Huami, Sony, Bose, Amazon, Nordic and Espressif, and Fast Pair, Find My Device, SmartTag, Tile, Xiaomi and exposure-notification beacons. Anything else is only heard with the screen on, so it may count as arriving again when the screen comes back on.
- **Scan limits.** Android stops delivering results from a scan that has run for 30 minutes, and ignores an app's scan starts beyond five in 30 seconds. nearby renews its scan every 25 minutes and spaces its starts to stay under the limit.
- **Addresses.** Android 15 and newer say whether an address is public or random. Older versions don't, so nearby treats an address whose top bits are `01` as rotating (resolvable) and any other as fixed. A device with a public address whose maker prefix starts with `01` is then misread as rotating.
- **Alerts.** The ping is the phone's notification sound. Arrival notifications use the *New devices* channel, which pops up but is silent itself, so sound follows the **Ping** setting. **Whitelist** on a notification works without opening the app.
- **Classic.** Bluetooth Classic inquiry isn't available on Android.
- **Data.** Stored as JSON in the app's private storage, and saved shortly after each change.

## Build and run

You need Flutter 3.47 or newer. Linux needs the desktop toolchain (`clang`, `cmake`, `ninja`, GTK 3 headers); Android needs the Android SDK and JDK 17 or newer.

```sh
cd app
flutter pub get
flutter test
flutter run -d linux             # debug, on this computer
flutter run                      # debug, on a connected phone
flutter build linux --release    # build/linux/x64/release/bundle/nearby
linux/packaging/install.sh       # installs to ~/.local/lib/nearby with a launcher entry
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
(cd android && ./gradlew :app:testDebugUnitTest)   # Kotlin unit tests, after a build
```

Install the APK with `adb install -r app-release.apk`, or copy it to the phone and open it. Release builds are signed with the debug key of the machine that built them, so an update installs over an earlier build only if it came from the same machine.

Releases are tagged by date, `vYYYY.M.D`, and built with that version:

```sh
flutter build apk --release --build-name=2026.10.22 --build-number=2026102200
```

CI builds the Linux bundle, with `packaging/install.sh` inside, as the `nearby-linux-x64` artifact, and the APK as `nearby-android-apk`. Both come from the *App* workflow.

To check a Linux adapter from the terminal without the UI:

```sh
dart run tool/scan.dart 15    # scan for 15 s and list what was heard, nearest first
```
