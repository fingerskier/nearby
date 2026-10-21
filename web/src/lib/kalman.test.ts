import { describe, expect, it } from 'vitest'
import { mulberry32 } from '../scan/demo'
import { Kalman1D } from './kalman'

function noisy(seed: number, count: number, mean: number, sigma: number): number[] {
  const random = mulberry32(seed)
  return Array.from({ length: count }, () => mean + (random() - 0.5) * 2 * sigma * Math.sqrt(3))
}

function variance(values: number[]): number {
  const mean = values.reduce((a, b) => a + b, 0) / values.length
  return values.reduce((a, b) => a + (b - mean) ** 2, 0) / values.length
}

describe('Kalman1D', () => {
  it('starts at the first reading', () => {
    const filter = new Kalman1D(1, 16)
    expect(Number.isNaN(filter.value)).toBe(true)
    expect(filter.update(-70, 0)).toBe(-70)
  })

  it('smooths a noisy constant signal', () => {
    const filter = new Kalman1D(1, 16)
    const input = noisy(1, 400, -70, 4)
    const output = input.map((z, i) => filter.update(z, i * 100))
    const settled = output.slice(100)
    expect(variance(settled)).toBeLessThan(variance(input) / 5)
    expect(settled.reduce((a, b) => a + b, 0) / settled.length).toBeCloseTo(-70, 0)
  })

  it('follows a step change, faster with more process noise', () => {
    const lag = (q: number) => {
      const filter = new Kalman1D(q, 16)
      for (let i = 0; i < 50; i++) filter.update(-60, i * 100)
      let steps = 0
      while (filter.update(-80, (50 + steps) * 100) > -75) steps++
      return steps
    }
    expect(lag(1)).toBeLessThan(60)
    expect(lag(10)).toBeLessThan(lag(1))
  })

  it('trusts a reading more after a long silence', () => {
    const quick = new Kalman1D(1, 16)
    const slow = new Kalman1D(1, 16)
    for (let i = 0; i < 20; i++) {
      quick.update(-60, i * 100)
      slow.update(-60, i * 100)
    }
    const afterShortGap = quick.update(-80, 2_000)
    const afterLongGap = slow.update(-80, 60_000)
    expect(afterLongGap).toBeLessThan(afterShortGap)
  })
})
