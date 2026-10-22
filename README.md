# nearby
Locate and map nearby devices

## Platforms
* Flutter app for all platforms
* WebApp
* ESP32, RP2040, RP2350

## Features
* Identify devices and give approximate distance based on signal strength
* Bluetooth (other if feasible)
* Map with relative locations

## Linux and Android app

A Flutter app in [`app/`](app/README.md) that watches for nearby Bluetooth devices: through BlueZ on Linux, and through Android's Bluetooth LE scanner on Android 12 and newer.

* On first launch it learns a whitelist from whatever is around.
* After that, it plays a ping and shows a notification when an unlisted device comes into range. The notification has a **Whitelist** button.
* Each device's estimated distance is shown on a radar, using the same model as the web app.
* On Android it keeps watching in the background, behind an ongoing notification with a **Stop** button.

```sh
cd app
flutter run -d linux
flutter build linux --release && linux/packaging/install.sh
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Releases are tagged by date, `vYYYY.M.D`.

## Web app
Live at <https://fingerskier.github.io/nearby/>, deployed from `main` by `.github/workflows/pages.yml`.

* **Scan** lists every Bluetooth advertisement in range. Chrome, Edge and Opera need `chrome://flags/#enable-experimental-web-platform-features` for this.
* **Add device** follows devices you pick one at a time in the browser's chooser, where full scanning is unavailable.
* **Demo** runs synthetic devices in any browser.

Distance comes from the log-distance path-loss model on Kalman-smoothed RSSI. Tune it under *Calibration*, or hold a device 1 m away and press its **1 m** button. A single receiver can't measure direction, so the map shows each device at its estimated distance but at an arbitrary angle.

```sh
cd web
npm install
npm run dev       # http://localhost:5173 (localhost counts as secure for Web Bluetooth)
npm run test:run
npm run build
```
