import { afterEach, describe, expect, it, vi } from 'vitest'
import { describeError, isChooserCancelled, LeScanSource, toSighting } from './bluetooth'

const device = { id: 'dev-1', name: 'Gatt name' }

describe('toSighting', () => {
  it('maps an advertisement', () => {
    expect(toSighting({ device, name: 'Adv name', rssi: -61, txPower: -8 }, 5)).toEqual({
      id: 'dev-1',
      name: 'Adv name',
      rssi: -61,
      txPower: -8,
      observer: 'local',
      at: 5,
    })
  })

  it('falls back to the device name and drops unavailable values', () => {
    const sighting = toSighting({ device, rssi: -70, txPower: 127 }, 0)
    expect(sighting?.name).toBe('Gatt name')
    expect(sighting?.txPower).toBeUndefined()
  })

  it('ignores advertisements without RSSI', () => {
    expect(toSighting({ device, rssi: undefined })).toBeNull()
    expect(toSighting({ device, rssi: 127 })).toBeNull()
  })
})

describe('LeScanSource', () => {
  afterEach(() => vi.unstubAllGlobals())

  function fakeBluetooth() {
    const scan = { active: true, stop: vi.fn() }
    let resolveScan: (value: typeof scan) => void = () => {}
    const listeners = new Set<(event: unknown) => void>()
    const bluetooth = {
      addEventListener: vi.fn((_: string, listener: (event: unknown) => void) => listeners.add(listener)),
      removeEventListener: vi.fn((_: string, listener: (event: unknown) => void) => listeners.delete(listener)),
      requestLEScan: vi.fn(() => new Promise<typeof scan>((resolve) => (resolveScan = resolve))),
    }
    vi.stubGlobal('navigator', { bluetooth })
    return { scan, bluetooth, listeners, resolve: () => resolveScan(scan) }
  }

  it('forwards advertisements and stops cleanly', async () => {
    const fake = fakeBluetooth()
    const emit = vi.fn()
    const source = new LeScanSource()
    const started = source.start(emit)
    fake.resolve()
    await started
    for (const listener of fake.listeners) listener({ device, rssi: -50 })
    expect(emit).toHaveBeenCalledWith(expect.objectContaining({ id: 'dev-1', rssi: -50 }))
    source.stop()
    expect(fake.scan.stop).toHaveBeenCalled()
    expect(fake.listeners.size).toBe(0)
  })

  it('stops a scan that resolves after stop() was called', async () => {
    const fake = fakeBluetooth()
    const source = new LeScanSource()
    const started = source.start(vi.fn())
    source.stop()
    fake.resolve()
    await started
    expect(fake.scan.stop).toHaveBeenCalled()
    expect(fake.listeners.size).toBe(0)
  })

  it('cleans up and rethrows when the scan is refused', async () => {
    const fake = fakeBluetooth()
    fake.bluetooth.requestLEScan.mockRejectedValueOnce(new DOMException('denied', 'NotAllowedError'))
    await expect(new LeScanSource().start(vi.fn())).rejects.toThrow('denied')
    expect(fake.listeners.size).toBe(0)
  })
})

describe('errors', () => {
  it('recognises a cancelled chooser', () => {
    expect(isChooserCancelled(new DOMException('User cancelled the requestDevice() chooser.', 'NotFoundError'))).toBe(
      true,
    )
    expect(isChooserCancelled(new DOMException('Bluetooth adapter not available.', 'NotFoundError'))).toBe(false)
  })

  it('explains common failures', () => {
    expect(describeError(new DOMException('x', 'NotAllowedError'))).toMatch(/permission/i)
    expect(describeError(new Error('boom'))).toBe('boom')
  })
})
