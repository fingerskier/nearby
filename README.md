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
