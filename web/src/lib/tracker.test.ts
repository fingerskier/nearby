import { describe, expect, it } from 'vitest'
import type { Sighting } from '../scan/types'
import { DEFAULT_SETTINGS, type Settings } from './settings'
import { angleFor, Tracker } from './tracker'

const settings: Settings = { ...DEFAULT_SETTINGS, staleSeconds: 10 }

function sighting(partial: Partial<Sighting> & { id: string; rssi: number; at: number }): Sighting {
  return { observer: 'local', ...partial }
}

describe('Tracker', () => {
  it('ranges a device from its smoothed RSSI', () => {
    const tracker = new Tracker(settings)
    for (let i = 0; i < 20; i++) tracker.ingest(sighting({ id: 'a', rssi: -79, at: i * 100 }))
    const [device] = tracker.devices()
    expect(device.count).toBe(20)
    expect(device.smoothed).toBeCloseTo(-79)
    expect(device.distance).toBeCloseTo(10)
  })

  it('keeps a name and TX power once seen', () => {
    const tracker = new Tracker(settings)
    tracker.ingest(sighting({ id: 'a', rssi: -60, at: 0, name: 'Tag', txPower: -10 }))
    tracker.ingest(sighting({ id: 'a', rssi: -60, at: 100 }))
    const [device] = tracker.devices()
    expect(device.name).toBe('Tag')
    expect(device.txPower).toBe(-10)
    expect(device.ref1m).toBe(-51)
  })

  it('sorts nearest first', () => {
    const tracker = new Tracker(settings)
    tracker.ingest(sighting({ id: 'far', rssi: -85, at: 0 }))
    tracker.ingest(sighting({ id: 'near', rssi: -50, at: 0 }))
    expect(tracker.devices().map((d) => d.id)).toEqual(['near', 'far'])
  })

  it('forgets devices after the stale window', () => {
    const tracker = new Tracker(settings)
    tracker.ingest(sighting({ id: 'old', rssi: -60, at: 0 }))
    tracker.ingest(sighting({ id: 'new', rssi: -60, at: 9_000 }))
    expect(tracker.prune(10_000)).toBe(0)
    expect(tracker.prune(10_001)).toBe(1)
    expect(tracker.devices().map((d) => d.id)).toEqual(['new'])
  })

  it('re-ranges existing devices when settings change', () => {
    const tracker = new Tracker(settings)
    tracker.ingest(sighting({ id: 'a', rssi: -79, at: 0 }))
    expect(tracker.devices()[0].distance).toBeCloseTo(10)
    tracker.configure({ ...settings, calibrations: { a: -69 } })
    const [device] = tracker.devices()
    expect(device.calibrated).toBe(true)
    expect(device.distance).toBeCloseTo(Math.sqrt(10))
  })

  it('hands out snapshots, not live state', () => {
    const tracker = new Tracker(settings)
    tracker.ingest(sighting({ id: 'a', rssi: -60, at: 0 }))
    const [before] = tracker.devices()
    tracker.ingest(sighting({ id: 'a', rssi: -90, at: 100 }))
    expect(before.rssi).toBe(-60)
  })
})

describe('angleFor', () => {
  it('is stable and within one turn', () => {
    expect(angleFor('abc')).toBe(angleFor('abc'))
    expect(angleFor('abc')).not.toBe(angleFor('abd'))
    for (const id of ['', 'x', 'Pl8vzu2hVCuHk/k0MHM1eA==']) {
      expect(angleFor(id)).toBeGreaterThanOrEqual(0)
      expect(angleFor(id)).toBeLessThan(2 * Math.PI)
    }
  })
})
