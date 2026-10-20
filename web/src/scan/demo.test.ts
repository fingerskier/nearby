import { describe, expect, it } from 'vitest'
import { distanceFromRssi } from '../lib/distance'
import type { Sighting } from './types'
import { mulberry32, Simulator } from './demo'

/** Advance in 100 ms ticks, as DemoSource does. */
function run(simulator: Simulator, until: number, onTick?: () => void): Sighting[] {
  const heard: Sighting[] = []
  for (let t = 100; t <= until; t += 100) {
    heard.push(...simulator.advance(t))
    onTick?.()
  }
  return heard
}

describe('mulberry32', () => {
  it('is deterministic and uniform-ish on [0, 1)', () => {
    const a = mulberry32(42)
    const b = mulberry32(42)
    const values = Array.from({ length: 1000 }, () => a())
    expect(values.slice(0, 5)).toEqual(Array.from({ length: 5 }, () => b()))
    expect(Math.min(...values)).toBeGreaterThanOrEqual(0)
    expect(Math.max(...values)).toBeLessThan(1)
    expect(values.reduce((s, v) => s + v, 0) / values.length).toBeCloseTo(0.5, 1)
  })
})

describe('Simulator', () => {
  it('replays identically for the same seed', () => {
    const first = run(new Simulator(0, 7), 5_000)
    const second = run(new Simulator(0, 7), 5_000)
    expect(first).toEqual(second)
    expect(first.length).toBeGreaterThan(50)
  })

  it('emits time-ordered sightings for every device', () => {
    const simulator = new Simulator(0, 3)
    const heard = run(simulator, 10_000)
    expect(heard.map((s) => s.at)).toEqual([...heard.map((s) => s.at)].sort((a, b) => a - b))
    const ids = new Set(heard.map((s) => s.id))
    // The passer-by may be out of range; everyone else advertises.
    expect(ids.size).toBeGreaterThanOrEqual(simulator.devices.length - 1)
  })

  it('produces RSSI consistent with each device’s true distance', () => {
    const simulator = new Simulator(0, 11)
    const stationary = simulator.devices.filter((d) => d.speed === 0)
    const heard = run(simulator, 60_000)
    for (const device of stationary) {
      const readings = heard.filter((s) => s.id === device.id).map((s) => s.rssi)
      const mean = readings.reduce((a, b) => a + b, 0) / readings.length
      const estimate = distanceFromRssi(mean, { ref1m: device.ref1m, n: 2 })
      expect(estimate / simulator.distanceTo(device)).toBeGreaterThan(0.8)
      expect(estimate / simulator.distanceTo(device)).toBeLessThan(1.25)
    }
  })

  it('keeps devices within range and stationary ones still', () => {
    const simulator = new Simulator(0, 5)
    const start = simulator.devices.map((d) => [d.x, d.y])
    run(simulator, 120_000, () => {
      for (const device of simulator.devices) {
        const r = Math.hypot(device.x, device.y)
        expect(r).toBeGreaterThanOrEqual(device.minR - 1e-9)
        expect(r).toBeLessThanOrEqual(device.maxR + 1e-9)
      }
    })
    simulator.devices.forEach((device, i) => {
      if (device.speed === 0) expect([device.x, device.y]).toEqual(start[i])
      else expect([device.x, device.y]).not.toEqual(start[i])
    })
  })

  it('does not replay a long pause in full', () => {
    const simulator = new Simulator(0, 9)
    run(simulator, 1_000)
    const afterPause = simulator.advance(3_600_000)
    expect(afterPause.length).toBeLessThan(200)
  })
})
