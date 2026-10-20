import { describe, expect, it } from 'vitest'
import { deviceLabel, formatAge, formatDistance, shortId } from './format'

describe('format', () => {
  it('formats distances with sensible precision', () => {
    expect(formatDistance(0.43)).toBe('0.4 m')
    expect(formatDistance(3.26)).toBe('3.3 m')
    expect(formatDistance(12.6)).toBe('13 m')
  })

  it('formats ages', () => {
    expect(formatAge(200)).toBe('now')
    expect(formatAge(4_400)).toBe('4 s')
    expect(formatAge(125_000)).toBe('2 min')
  })

  it('labels unnamed devices by a short id', () => {
    expect(shortId('Pl8vzu2hVCuHk/k0MHM1eA==')).toBe('Pl8vzu2h…')
    expect(deviceLabel({ id: 'Pl8vzu2hVCuHk/k0MHM1eA==' })).toBe('Pl8vzu2h…')
    expect(deviceLabel({ id: 'x', name: 'Watch' })).toBe('Watch')
  })
})
