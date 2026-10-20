import { useEffect, useState } from 'react'
import { DeviceList } from './components/DeviceList'
import { Radar } from './components/Radar'
import { SettingsPanel } from './components/SettingsPanel'
import { SupportNotice } from './components/SupportNotice'
import { loadSettings, saveSettings, type Settings } from './lib/settings'
import type { TrackedDevice } from './lib/tracker'
import { detectSupport, LeScanSource } from './scan/bluetooth'
import { DemoSource } from './scan/demo'
import type { SourceKind } from './scan/types'
import { useNearby } from './useNearby'

const STATUS: Record<SourceKind, string> = {
  scan: 'Scanning',
  watch: 'Watching chosen devices',
  demo: 'Demo — synthetic devices',
}

export default function App() {
  const [support] = useState(detectSupport)
  const [available, setAvailable] = useState<boolean | null>(null)
  const [settings, setSettings] = useState<Settings>(loadSettings)
  const [selected, setSelected] = useState<string | null>(null)
  const { devices, now, kind, error, start, stop, addDevice, clear } = useNearby(settings)

  useEffect(() => saveSettings(settings), [settings])

  useEffect(() => {
    if (!support.api) return
    navigator.bluetooth.getAvailability().then(setAvailable, () => setAvailable(null))
  }, [support.api])

  function calibrate(device: TrackedDevice) {
    setSettings({ ...settings, calibrations: { ...settings.calibrations, [device.id]: Math.round(device.smoothed) } })
  }

  function uncalibrate(device: TrackedDevice) {
    const calibrations = { ...settings.calibrations }
    delete calibrations[device.id]
    setSettings({ ...settings, calibrations })
  }

  const canScan = support.secure && support.scan
  const canWatch = support.secure && support.watch

  return (
    <div className="app">
      <header>
        <h1>
          <img src="./favicon.svg" alt="" width="24" height="24" /> nearby
        </h1>
        <p className="status" role="status">
          {kind ? STATUS[kind] : 'Idle'} · {devices.length} device{devices.length === 1 ? '' : 's'}
        </p>
        <nav className="controls" aria-label="Scanning">
          <button
            type="button"
            className="primary"
            disabled={!canScan}
            title={canScan ? 'Scan every Bluetooth advertisement in range' : 'Needs Web Bluetooth scanning (see note)'}
            onClick={() => start(new LeScanSource())}
          >
            Scan
          </button>
          <button
            type="button"
            disabled={!canWatch}
            title={canWatch ? 'Pick a device in the browser chooser and follow its signal' : 'Not supported here'}
            onClick={addDevice}
          >
            Add device
          </button>
          <button type="button" onClick={() => start(new DemoSource())}>
            Demo
          </button>
          <button type="button" disabled={!kind} onClick={stop}>
            Stop
          </button>
          <button type="button" disabled={devices.length === 0} onClick={clear}>
            Clear
          </button>
        </nav>
      </header>

      <SupportNotice support={support} available={available} />
      {error && (
        <p className="notice error" role="alert">
          {error}
        </p>
      )}

      <main>
        <section className="panel" aria-label="Map">
          <Radar
            devices={devices}
            now={now}
            staleMs={settings.staleSeconds * 1000}
            selected={selected}
            onSelect={setSelected}
          />
          <p className="caption">
            Distance from the centre is estimated from signal strength. One receiver can&apos;t tell direction, so
            each device&apos;s angle is arbitrary but stable.
          </p>
        </section>
        <section className="panel" aria-label="Devices">
          <DeviceList
            devices={devices}
            now={now}
            selected={selected}
            onSelect={setSelected}
            onCalibrate={calibrate}
            onUncalibrate={uncalibrate}
          />
        </section>
      </main>

      <details className="panel settings">
        <summary>Calibration</summary>
        <SettingsPanel settings={settings} onChange={setSettings} />
      </details>

      <footer>
        <a href="https://github.com/fingerskier/nearby">fingerskier/nearby</a> · Distances are rough: walls, bodies
        and antenna orientation easily shift readings by several metres.
      </footer>
    </div>
  )
}
