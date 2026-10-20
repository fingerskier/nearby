import { afterEach, describe, expect, it, vi } from 'vitest'
import { describeError, isChooserCancelled, LeScanSource, toSighting, WatchSource } from './bluetooth'

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

describe('WatchSource', () => {
  afterEach(() => vi.unstubAllGlobals())

  function fakeDevice(id: string) {
    const listeners = new Set<(event: unknown) => void>()
    const device = {
      id,
      name: id,
      watchingAdvertisements: false,
      addEventListener: vi.fn((_: string, listener: (event: unknown) => void) => listeners.add(listener)),
      removeEventListener: vi.fn((_: string, listener: (event: unknown) => void) => listeners.delete(listener)),
      watchAdvertisements: vi.fn(async () => {
        device.watchingAdvertisements = true
      }),
    }
    return { device, listeners }
  }

  function setup() {
    const doc = Object.assign(new EventTarget(), { visibilityState: 'visible' })
    const picked = fakeDevice('dev-1')
    vi.stubGlobal('document', doc)
    vi.stubGlobal('navigator', { bluetooth: { requestDevice: vi.fn(async () => picked.device) } })
    return { doc, ...picked }
  }

  it('forwards advertisements from a picked device', async () => {
    const { device, listeners } = setup()
    const emit = vi.fn()
    const source = new WatchSource()
    await source.start(emit)
    await source.add()
    expect(device.watchAdvertisements).toHaveBeenCalledTimes(1)
    for (const listener of listeners) listener({ device, rssi: -55 })
    expect(emit).toHaveBeenCalledWith(expect.objectContaining({ id: 'dev-1', rssi: -55 }))
  })

  it('does not double-watch a device that is still watching', async () => {
    const { device, listeners } = setup()
    const source = new WatchSource()
    await source.start(vi.fn())
    await source.add()
    await source.add()
    expect(device.watchAdvertisements).toHaveBeenCalledTimes(1)
    expect(listeners.size).toBe(1)
  })

  it('restarts a lapsed watch when the device is picked again', async () => {
    const { device, listeners } = setup()
    const source = new WatchSource()
    await source.start(vi.fn())
    await source.add()
    device.watchingAdvertisements = false
    await source.add()
    expect(device.watchAdvertisements).toHaveBeenCalledTimes(2)
    expect(listeners.size).toBe(1)
  })

  it('resumes lapsed watches when the page becomes visible', async () => {
    const { doc, device } = setup()
    const source = new WatchSource()
    await source.start(vi.fn())
    await source.add()
    device.watchingAdvertisements = false
    doc.dispatchEvent(new Event('visibilitychange'))
    await Promise.resolve()
    expect(device.watchAdvertisements).toHaveBeenCalledTimes(2)
  })

  it('stops watching and listening on stop()', async () => {
    const { doc, device, listeners } = setup()
    const source = new WatchSource()
    await source.start(vi.fn())
    await source.add()
    const signal = (device.watchAdvertisements.mock.calls[0] as unknown as [{ signal: AbortSignal }])[0].signal
    source.stop()
    expect(signal.aborted).toBe(true)
    expect(listeners.size).toBe(0)
    device.watchingAdvertisements = false
    doc.dispatchEvent(new Event('visibilitychange'))
    expect(device.watchAdvertisements).toHaveBeenCalledTimes(1)
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
