export interface Settings {
  /** Path-loss exponent. */
  n: number
  /** Default RSSI at 1 m, dBm, for devices without calibration or TX power. */
  ref1m: number
  /** Derive the 1 m reference from advertised TX power when present. */
  useTxPower: boolean
  /** Standard deviation of a single RSSI reading, dB; higher smooths more. */
  noiseDb: number
  /** Drop devices not heard from for this long. */
  staleSeconds: number
  /** Per-device 1 m reference, dBm, keyed by device id. */
  calibrations: Record<string, number>
}

export const DEFAULT_SETTINGS: Settings = {
  n: 2,
  ref1m: -59,
  useTxPower: true,
  noiseDb: 4,
  staleSeconds: 20,
  calibrations: {},
}

type NumericKey = 'n' | 'ref1m' | 'noiseDb' | 'staleSeconds'

export const LIMITS: Record<NumericKey, { min: number; max: number; step: number }> = {
  n: { min: 1.5, max: 5, step: 0.1 },
  ref1m: { min: -100, max: -20, step: 1 },
  noiseDb: { min: 1, max: 12, step: 0.5 },
  staleSeconds: { min: 5, max: 300, step: 5 },
}

/** Process noise for the RSSI filter, dB²/s: lets the estimate follow a walking-pace change in a few seconds. */
export const PROCESS_NOISE = 1

const STORAGE_KEY = 'nearby.settings'

function clampNumber(value: unknown, key: NumericKey): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_SETTINGS[key]
  return Math.min(LIMITS[key].max, Math.max(LIMITS[key].min, value))
}

/** Accepts anything (e.g. parsed JSON from storage) and returns valid settings, falling back per field. */
export function parseSettings(raw: unknown): Settings {
  const input = typeof raw === 'object' && raw !== null ? (raw as Record<string, unknown>) : {}
  const calibrations: Record<string, number> = {}
  if (typeof input.calibrations === 'object' && input.calibrations !== null && !Array.isArray(input.calibrations)) {
    for (const [id, value] of Object.entries(input.calibrations)) {
      if (typeof value === 'number' && Number.isFinite(value)) calibrations[id] = value
    }
  }
  return {
    n: clampNumber(input.n, 'n'),
    ref1m: clampNumber(input.ref1m, 'ref1m'),
    useTxPower: typeof input.useTxPower === 'boolean' ? input.useTxPower : DEFAULT_SETTINGS.useTxPower,
    noiseDb: clampNumber(input.noiseDb, 'noiseDb'),
    staleSeconds: clampNumber(input.staleSeconds, 'staleSeconds'),
    calibrations,
  }
}

export function loadSettings(): Settings {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    return parseSettings(stored ? JSON.parse(stored) : null)
  } catch {
    return parseSettings(null)
  }
}

export function saveSettings(settings: Settings): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings))
  } catch {
    // Storage can be unavailable (private mode, blocked site data); settings just won't persist.
  }
}
