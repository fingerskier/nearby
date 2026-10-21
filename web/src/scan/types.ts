/** One advertisement heard by one receiver. */
export interface Sighting {
  /** Advertiser id as exposed by the scanner (Web Bluetooth ids are per-origin and opaque). */
  id: string
  name?: string
  /** Received signal strength, dBm. */
  rssi: number
  /** Advertised TX power level, dBm, when the packet carries one. */
  txPower?: number
  /** Receiver that heard it: this browser is LOCAL_OBSERVER; firmware nodes will report their own ids. */
  observer: string
  /** Milliseconds since the epoch. */
  at: number
}

export const LOCAL_OBSERVER = 'local'

export type SourceKind = 'scan' | 'watch' | 'demo'

export interface ScanSource {
  readonly kind: SourceKind
  /** Begin delivering sightings. Bluetooth sources must be started from a user gesture. */
  start(emit: (sighting: Sighting) => void): Promise<void>
  /** Idempotent; safe to call while start() is still pending. */
  stop(): void
}
