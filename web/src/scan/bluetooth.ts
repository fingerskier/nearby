import { LOCAL_OBSERVER, type ScanSource, type Sighting } from './types'

export interface BluetoothSupport {
  /** HTTPS or localhost; Web Bluetooth is unavailable otherwise. */
  secure: boolean
  /** navigator.bluetooth exists. */
  api: boolean
  /** requestLEScan(): passive scan of every advertisement (Chrome: Experimental Web Platform features). */
  scan: boolean
  /** watchAdvertisements(): RSSI for devices picked one at a time in the browser's chooser. */
  watch: boolean
}

export function detectSupport(): BluetoothSupport {
  const secure = globalThis.isSecureContext === true
  const api = typeof navigator !== 'undefined' && 'bluetooth' in navigator
  const deviceClass = (globalThis as { BluetoothDevice?: { prototype: Partial<BluetoothDevice> } }).BluetoothDevice
  return {
    secure,
    api,
    scan: api && typeof navigator.bluetooth.requestLEScan === 'function',
    watch: api && typeof deviceClass?.prototype.watchAdvertisements === 'function',
  }
}

/** BLE reports 127 when RSSI or TX power is not available. */
const UNAVAILABLE = 127

type Advertisement = Pick<BluetoothAdvertisingEvent, 'name' | 'rssi' | 'txPower'> & {
  device: Pick<BluetoothDevice, 'id' | 'name'>
}

export function toSighting(event: Advertisement, at = Date.now()): Sighting | null {
  if (typeof event.rssi !== 'number' || event.rssi === UNAVAILABLE) return null
  const txPower = typeof event.txPower === 'number' && event.txPower !== UNAVAILABLE ? event.txPower : undefined
  return {
    id: event.device.id,
    name: event.name || event.device.name || undefined,
    rssi: event.rssi,
    txPower,
    observer: LOCAL_OBSERVER,
    at,
  }
}

/** Every advertisement in range, via navigator.bluetooth.requestLEScan(). */
export class LeScanSource implements ScanSource {
  readonly kind = 'scan'
  private scan?: BluetoothLEScan
  private listener?: (event: BluetoothAdvertisingEvent) => void
  private stopped = false

  async start(emit: (sighting: Sighting) => void): Promise<void> {
    const bluetooth = navigator.bluetooth
    const listener = (event: BluetoothAdvertisingEvent) => {
      const sighting = toSighting(event)
      if (sighting) emit(sighting)
    }
    this.listener = listener
    bluetooth.addEventListener('advertisementreceived', listener)
    let scan: BluetoothLEScan
    try {
      scan = await bluetooth.requestLEScan({ acceptAllAdvertisements: true, keepRepeatedDevices: true })
    } catch (error) {
      this.stop()
      throw error
    }
    if (this.stopped) scan.stop()
    else this.scan = scan
  }

  stop(): void {
    this.stopped = true
    this.scan?.stop()
    this.scan = undefined
    if (this.listener) navigator.bluetooth.removeEventListener('advertisementreceived', this.listener)
    this.listener = undefined
  }
}

interface Watch {
  device: BluetoothDevice
  abort: AbortController
  listener: (event: BluetoothAdvertisingEvent) => void
}

/** Devices chosen one at a time in the browser's picker, each followed with watchAdvertisements(). */
export class WatchSource implements ScanSource {
  readonly kind = 'watch'
  private emit?: (sighting: Sighting) => void
  private watches = new Map<string, Watch>()

  /** Browsers abort watches while the page is hidden; pick them back up when it is visible again. */
  private readonly onVisibilityChange = () => {
    if (document.visibilityState !== 'visible') return
    for (const { device } of [...this.watches.values()]) {
      if (!device.watchingAdvertisements) this.watch(device).catch(() => {})
    }
  }

  async start(emit: (sighting: Sighting) => void): Promise<void> {
    this.emit = emit
    document.addEventListener('visibilitychange', this.onVisibilityChange)
  }

  /** Opens the device chooser, so it must run from a user gesture. Re-picking a lapsed device restarts its watch. */
  async add(): Promise<void> {
    const device = await navigator.bluetooth.requestDevice({ acceptAllDevices: true })
    if (this.watches.get(device.id)?.device.watchingAdvertisements) return
    await this.watch(device)
  }

  stop(): void {
    document.removeEventListener('visibilitychange', this.onVisibilityChange)
    for (const id of [...this.watches.keys()]) this.unwatch(id)
    this.emit = undefined
  }

  private async watch(device: BluetoothDevice): Promise<void> {
    const emit = this.emit
    if (!emit) return
    this.unwatch(device.id)
    const watch: Watch = {
      device,
      abort: new AbortController(),
      listener: (event) => {
        const sighting = toSighting(event)
        if (sighting) emit(sighting)
      },
    }
    device.addEventListener('advertisementreceived', watch.listener)
    this.watches.set(device.id, watch)
    try {
      await device.watchAdvertisements({ signal: watch.abort.signal })
    } catch (error) {
      if (watch.abort.signal.aborted) return
      if (this.watches.get(device.id) === watch) this.unwatch(device.id)
      throw error
    }
  }

  private unwatch(id: string): void {
    const watch = this.watches.get(id)
    if (!watch) return
    watch.abort.abort()
    watch.device.removeEventListener('advertisementreceived', watch.listener)
    this.watches.delete(id)
  }
}

/** The chooser was dismissed without picking a device. */
export function isChooserCancelled(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'NotFoundError' && /cancel/i.test(error.message)
}

export function describeError(error: unknown): string {
  if (error instanceof DOMException) {
    switch (error.name) {
      case 'NotAllowedError':
        return 'Bluetooth permission was denied. Allow it for this site and try again.'
      case 'SecurityError':
        return 'Web Bluetooth needs a secure (HTTPS) page.'
      case 'NotFoundError':
        return 'No Bluetooth adapter is available. Is Bluetooth turned on?'
    }
    return `${error.name}: ${error.message}`
  }
  return error instanceof Error ? error.message : String(error)
}
