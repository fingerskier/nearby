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

/** Devices chosen one at a time in the browser's picker, each followed with watchAdvertisements(). */
export class WatchSource implements ScanSource {
  readonly kind = 'watch'
  private emit?: (sighting: Sighting) => void
  private watched = new Map<string, () => void>()

  get count(): number {
    return this.watched.size
  }

  async start(emit: (sighting: Sighting) => void): Promise<void> {
    this.emit = emit
  }

  /** Opens the device chooser, so it must run from a user gesture. */
  async add(): Promise<void> {
    const device = await navigator.bluetooth.requestDevice({ acceptAllDevices: true })
    const emit = this.emit
    if (!emit || this.watched.has(device.id)) return
    const abort = new AbortController()
    const listener = (event: BluetoothAdvertisingEvent) => {
      const sighting = toSighting(event)
      if (sighting) emit(sighting)
    }
    device.addEventListener('advertisementreceived', listener)
    const unwatch = () => {
      abort.abort()
      device.removeEventListener('advertisementreceived', listener)
    }
    this.watched.set(device.id, unwatch)
    try {
      await device.watchAdvertisements({ signal: abort.signal })
    } catch (error) {
      if (abort.signal.aborted) return
      unwatch()
      this.watched.delete(device.id)
      throw error
    }
  }

  stop(): void {
    for (const unwatch of this.watched.values()) unwatch()
    this.watched.clear()
    this.emit = undefined
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
