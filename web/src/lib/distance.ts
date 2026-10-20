/** Log-distance path-loss model: rssi = ref1m − 10·n·log10(d). */
export interface PathLoss {
  /** Expected RSSI at 1 m, dBm. */
  ref1m: number
  /** Path-loss exponent: ~2 in open space, 2.5–4 indoors and through obstacles. */
  n: number
}

/**
 * Converts an advertised TX power (dBm at the antenna) to an RSSI-at-1 m reference:
 * free-space loss at 1 m on 2.4 GHz is ~40 dB, plus ~1 dB of receiver/body loss.
 */
export const TX_POWER_TO_REF1M = 41

/** Estimates are clamped to this range; beyond it the model says nothing useful. */
export const MIN_DISTANCE = 0.1
export const MAX_DISTANCE = 100

export function distanceFromRssi(rssi: number, { ref1m, n }: PathLoss): number {
  const d = 10 ** ((ref1m - rssi) / (10 * n))
  return Math.min(MAX_DISTANCE, Math.max(MIN_DISTANCE, d))
}

export function rssiAtDistance(distance: number, { ref1m, n }: PathLoss): number {
  return ref1m - 10 * n * Math.log10(distance)
}

/** The 1 m reference for one device: a per-device calibration wins, then advertised TX power, then the default. */
export function resolveRef1m(options: {
  calibrated?: number
  txPower?: number
  useTxPower: boolean
  fallback: number
}): number {
  if (options.calibrated !== undefined) return options.calibrated
  if (options.useTxPower && options.txPower !== undefined) return options.txPower - TX_POWER_TO_REF1M
  return options.fallback
}
