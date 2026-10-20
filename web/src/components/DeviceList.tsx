import { formatAge, formatDistance, shortId } from '../lib/format'
import type { TrackedDevice } from '../lib/tracker'

interface Props {
  devices: TrackedDevice[]
  now: number
  selected: string | null
  onSelect: (id: string | null) => void
  onCalibrate: (device: TrackedDevice) => void
  onUncalibrate: (device: TrackedDevice) => void
}

export function DeviceList({ devices, now, selected, onSelect, onCalibrate, onUncalibrate }: Props) {
  if (devices.length === 0) return <p className="empty">No devices in range yet.</p>

  return (
    <table className="devices">
      <thead>
        <tr>
          <th>Device</th>
          <th className="num">Distance</th>
          <th className="num">RSSI</th>
          <th className="num seen">Seen</th>
          <th>
            <span className="visually-hidden">Calibration</span>
          </th>
        </tr>
      </thead>
      <tbody>
        {devices.map((device) => (
          <tr key={device.id} className={device.id === selected ? 'selected' : undefined}>
            <td>
              <button
                type="button"
                className="link"
                aria-pressed={device.id === selected}
                onClick={() => onSelect(device.id === selected ? null : device.id)}
              >
                {device.name ?? <span className="unnamed">Unnamed</span>}
              </button>
              <div className="id" title={device.id}>
                {shortId(device.id)}
                {device.txPower !== undefined && <> · TX {device.txPower} dBm</>}
              </div>
            </td>
            <td className="num">≈ {formatDistance(device.distance)}</td>
            <td className="num">
              {Math.round(device.smoothed)}
              <span className="raw" title="Latest raw reading">
                {' '}
                ({device.rssi})
              </span>
            </td>
            <td className="num seen">{formatAge(now - device.lastSeen)}</td>
            <td>
              {device.calibrated ? (
                <button
                  type="button"
                  className="small active"
                  title={`Calibrated: ${Math.round(device.ref1m)} dBm at 1 m. Click to remove.`}
                  onClick={() => onUncalibrate(device)}
                >
                  1 m ✓
                </button>
              ) : (
                <button
                  type="button"
                  className="small"
                  title="Hold this device 1 m away, wait a few seconds, then click to use its current signal as its 1 m reference"
                  onClick={() => onCalibrate(device)}
                >
                  1 m
                </button>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
