import { describe, expect, it } from 'vitest'
import { nextRange, radiusFor } from './radarScale'

describe('nextRange', () => {
  it('grows straight to the ring that fits the farthest device', () => {
    expect(nextRange(5, 12)).toBe(20)
    expect(nextRange(2, 60)).toBe(100)
    expect(nextRange(100, 400)).toBe(100)
  })

  it('never goes below the minimum range', () => {
    expect(nextRange(2, 0)).toBe(2)
    expect(nextRange(2, 0.4)).toBe(2)
  })

  it('shrinks one ring at a time, only with clear margin', () => {
    expect(nextRange(20, 9)).toBe(20)
    expect(nextRange(20, 7)).toBe(10)
    expect(nextRange(20, 1)).toBe(10)
    expect(nextRange(10, 1)).toBe(5)
  })
})

describe('radiusFor', () => {
  it('maps 0 to the centre and the range to the edge', () => {
    expect(radiusFor(0, 10, 100)).toBe(0)
    expect(radiusFor(10, 10, 100)).toBeCloseTo(100)
    expect(radiusFor(50, 10, 100)).toBeCloseTo(100)
  })

  it('is monotonic and gives near devices more room than linear', () => {
    expect(radiusFor(1, 20, 100)).toBeGreaterThan(100 / 20)
    expect(radiusFor(2, 20, 100)).toBeGreaterThan(radiusFor(1, 20, 100))
  })
})
