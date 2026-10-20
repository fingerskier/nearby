import type { Sighting } from '../scan/types'
import { distanceFromRssi, resolveRef1m } from './distance'
import { Kalman1D } from './kalman'
import { PROCESS_NOISE, type Settings } from './settings'

export interface TrackedDevice {
  id: string
  name?: string
  observer: string
  /** Latest raw reading, dBm. */
  rssi: number
  /** Filtered RSSI, dBm. */
  smoothed: number
  txPower?: number
  /** RSSI expected at 1 m for this device. */
  ref1m: number
  /** Estimated distance, metres. */
  distance: number
  calibrated: boolean
  firstSeen: number
  lastSeen: number
  /** Advertisements received. */
  count: number
  /** Stable pseudo-bearing in radians; one receiver measures range only, never direction. */
  angle: number
}

/** FNV-1a, mapped onto [0, 2π). */
export function angleFor(id: string): number {
  let hash = 0x811c9dc5
  for (let i = 0; i < id.length; i++) {
    hash ^= id.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return ((hash >>> 0) / 0x100000000) * 2 * Math.PI
}

interface Entry {
  device: TrackedDevice
  filter: Kalman1D
}

/** Turns a stream of sightings into smoothed, ranged devices. */
export class Tracker {
  private entries = new Map<string, Entry>()
  private settings: Settings

  constructor(settings: Settings) {
    this.settings = settings
  }

  get size(): number {
    return this.entries.size
  }

  configure(settings: Settings): void {
    this.settings = settings
    for (const entry of this.entries.values()) {
      entry.filter.r = settings.noiseDb ** 2
      this.range(entry.device)
    }
  }

  ingest(sighting: Sighting): void {
    let entry = this.entries.get(sighting.id)
    if (!entry) {
      entry = {
        filter: new Kalman1D(PROCESS_NOISE, this.settings.noiseDb ** 2),
        device: {
          id: sighting.id,
          observer: sighting.observer,
          rssi: sighting.rssi,
          smoothed: sighting.rssi,
          ref1m: this.settings.ref1m,
          distance: 0,
          calibrated: false,
          firstSeen: sighting.at,
          lastSeen: sighting.at,
          count: 0,
          angle: angleFor(sighting.id),
        },
      }
      this.entries.set(sighting.id, entry)
    }
    const { device } = entry
    // Names and TX power often arrive in only some packets (e.g. scan responses), so keep the last known value.
    device.name = sighting.name ?? device.name
    device.txPower = sighting.txPower ?? device.txPower
    device.observer = sighting.observer
    device.rssi = sighting.rssi
    device.smoothed = entry.filter.update(sighting.rssi, sighting.at)
    device.lastSeen = Math.max(device.lastSeen, sighting.at)
    device.count += 1
    this.range(device)
  }

  /** Forget devices not heard from within the stale window; returns how many were dropped. */
  prune(now: number): number {
    const cutoff = now - this.settings.staleSeconds * 1000
    let removed = 0
    for (const [id, entry] of this.entries) {
      if (entry.device.lastSeen < cutoff) {
        this.entries.delete(id)
        removed += 1
      }
    }
    return removed
  }

  /** Snapshot copies, nearest first. */
  devices(): TrackedDevice[] {
    return [...this.entries.values()]
      .map((entry) => ({ ...entry.device }))
      .sort((a, b) => a.distance - b.distance || a.id.localeCompare(b.id))
  }

  clear(): void {
    this.entries.clear()
  }

  private range(device: TrackedDevice): void {
    const calibrated = this.settings.calibrations[device.id]
    device.calibrated = calibrated !== undefined
    device.ref1m = resolveRef1m({
      calibrated,
      txPower: device.txPower,
      useTxPower: this.settings.useTxPower,
      fallback: this.settings.ref1m,
    })
    device.distance = distanceFromRssi(device.smoothed, { ref1m: device.ref1m, n: this.settings.n })
  }
}
