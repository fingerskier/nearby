import { describe, expect, it } from 'vitest'
import { distanceFromRssi, MAX_DISTANCE, MIN_DISTANCE, resolveRef1m, rssiAtDistance } from './distance'

const model = { ref1m: -59, n: 2 }

describe('distanceFromRssi', () => {
  it('is 1 m at the reference RSSI', () => {
    expect(distanceFromRssi(-59, model)).toBeCloseTo(1)
  })

  it('grows tenfold for every 10·n dB of extra loss', () => {
    expect(distanceFromRssi(-79, model)).toBeCloseTo(10)
    expect(distanceFromRssi(-89, { ref1m: -59, n: 3 })).toBeCloseTo(10)
  })

  it('inverts rssiAtDistance', () => {
    for (const d of [0.3, 1, 2.5, 7, 40]) {
      expect(distanceFromRssi(rssiAtDistance(d, model), model)).toBeCloseTo(d)
    }
  })

  it('clamps to the useful range', () => {
    expect(distanceFromRssi(-10, model)).toBe(MIN_DISTANCE)
    expect(distanceFromRssi(-140, model)).toBe(MAX_DISTANCE)
  })
})

describe('resolveRef1m', () => {
  it('prefers calibration, then TX power, then the fallback', () => {
    expect(resolveRef1m({ calibrated: -50, txPower: 0, useTxPower: true, fallback: -59 })).toBe(-50)
    expect(resolveRef1m({ txPower: 0, useTxPower: true, fallback: -59 })).toBe(-41)
    expect(resolveRef1m({ txPower: 0, useTxPower: false, fallback: -59 })).toBe(-59)
    expect(resolveRef1m({ useTxPower: true, fallback: -59 })).toBe(-59)
  })
})
