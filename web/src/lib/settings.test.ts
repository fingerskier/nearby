import { describe, expect, it } from 'vitest'
import { DEFAULT_SETTINGS, LIMITS, parseSettings } from './settings'

describe('parseSettings', () => {
  it('falls back to defaults for missing or malformed input', () => {
    expect(parseSettings(null)).toEqual(DEFAULT_SETTINGS)
    expect(parseSettings('nope')).toEqual(DEFAULT_SETTINGS)
    expect(parseSettings({ n: 'two', useTxPower: 'yes', calibrations: [1] })).toEqual(DEFAULT_SETTINGS)
  })

  it('keeps valid values and clamps out-of-range ones', () => {
    const parsed = parseSettings({ n: 9, ref1m: -65, staleSeconds: 1, noiseDb: 3, useTxPower: false })
    expect(parsed.n).toBe(LIMITS.n.max)
    expect(parsed.ref1m).toBe(-65)
    expect(parsed.staleSeconds).toBe(LIMITS.staleSeconds.min)
    expect(parsed.noiseDb).toBe(3)
    expect(parsed.useTxPower).toBe(false)
  })

  it('keeps only numeric calibrations', () => {
    expect(parseSettings({ calibrations: { a: -60, b: 'x', c: Number.NaN } }).calibrations).toEqual({ a: -60 })
  })
})
