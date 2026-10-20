import { rssiAtDistance, TX_POWER_TO_REF1M } from '../lib/distance'
import { LOCAL_OBSERVER, type ScanSource, type Sighting } from './types'

/** Seeded PRNG (mulberry32), so a demo world and its tests are repeatable. */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

interface Profile {
  name?: string
  /** True RSSI at 1 m; real devices differ, which is why per-device calibration exists. */
  ref1m: number
  txPower?: number
  intervalMs: number
  /** Wanders within this annulus around the observer, metres. */
  minR: number
  maxR: number
  /** Metres per second; 0 is stationary. */
  speed: number
  /** In range for onMs, then silent for offMs, repeating. */
  presence?: { onMs: number; offMs: number }
}

const PROFILES: Profile[] = [
  { name: 'Phone', ref1m: -57, intervalMs: 250, minR: 1, maxR: 6, speed: 0.6 },
  { name: 'Watch', ref1m: -62, intervalMs: 500, minR: 0.4, maxR: 1.2, speed: 0.2 },
  { name: 'Earbuds case', ref1m: -60, intervalMs: 300, minR: 1.5, maxR: 1.5, speed: 0 },
  { name: 'Laptop', ref1m: -56, intervalMs: 400, minR: 2.5, maxR: 2.5, speed: 0 },
  { name: 'Speaker', ref1m: -14 - TX_POWER_TO_REF1M, txPower: -14, intervalMs: 200, minR: 4, maxR: 4, speed: 0 },
  { name: 'Beacon', ref1m: -20 - TX_POWER_TO_REF1M, txPower: -20, intervalMs: 1000, minR: 9, maxR: 9, speed: 0 },
  { ref1m: -60, intervalMs: 600, minR: 3, maxR: 12, speed: 1.2, presence: { onMs: 40_000, offMs: 30_000 } },
  { ref1m: -59, intervalMs: 800, minR: 15, maxR: 25, speed: 0.8 },
]

/** Typical indoor RSSI scatter, dB. */
const NOISE_DB = 4
/** Fraction of advertisements lost to collisions and fading. */
const DROP_RATE = 0.1
/** After a long pause (background tab) resume instead of replaying every missed advertisement. */
const MAX_CATCH_UP_MS = 2_000
const TRUE_EXPONENT = 2

export interface SimDevice extends Profile {
  id: string
  /** Position in polar form around the observer; x and y mirror it. */
  r: number
  theta: number
  x: number
  y: number
  targetR: number
  targetTheta: number
  movedAt: number
  nextAt: number
  phase: number
}

/** A small synthetic world of advertisers around the observer at (0, 0). */
export class Simulator {
  readonly devices: SimDevice[]
  private random: () => number

  constructor(now: number, seed = now) {
    this.random = mulberry32(seed)
    this.devices = PROFILES.map((profile) => {
      const [r, theta] = this.pointIn(profile.minR, profile.maxR)
      const [targetR, targetTheta] = this.pointIn(profile.minR, profile.maxR)
      return {
        ...profile,
        id: this.makeId(),
        r,
        theta,
        x: r * Math.cos(theta),
        y: r * Math.sin(theta),
        targetR,
        targetTheta,
        movedAt: now,
        nextAt: now + this.random() * profile.intervalMs,
        phase: this.random() * 60_000,
      }
    })
  }

  distanceTo(device: SimDevice): number {
    return Math.max(0.1, device.r)
  }

  /** Move the world forward to `now` and return the advertisements heard on the way, oldest first. */
  advance(now: number): Sighting[] {
    const heard: Sighting[] = []
    for (const device of this.devices) {
      if (now - device.nextAt > MAX_CATCH_UP_MS) {
        device.nextAt = now - MAX_CATCH_UP_MS
        device.movedAt = Math.max(device.movedAt, device.nextAt)
      }
      while (device.nextAt <= now) {
        const at = device.nextAt
        this.move(device, at)
        if (this.present(device, at) && this.random() >= DROP_RATE) heard.push(this.sight(device, at))
        device.nextAt += device.intervalMs * (0.9 + 0.2 * this.random())
      }
    }
    return heard.sort((a, b) => a.at - b.at)
  }

  private present(device: SimDevice, at: number): boolean {
    if (!device.presence) return true
    const { onMs, offMs } = device.presence
    return (at + device.phase) % (onMs + offMs) < onMs
  }

  /** Radius and bearing are interpolated separately, so a path never cuts inside minR the way a chord would. */
  private move(device: SimDevice, at: number): void {
    let budget = (device.speed * (at - device.movedAt)) / 1000
    device.movedAt = at
    while (budget > 0) {
      const dr = device.targetR - device.r
      const dTheta = wrapAngle(device.targetTheta - device.theta)
      const gap = Math.hypot(dr, ((device.r + device.targetR) / 2) * dTheta)
      if (gap <= budget) {
        device.r = device.targetR
        device.theta = device.targetTheta
        budget -= gap
        ;[device.targetR, device.targetTheta] = this.pointIn(device.minR, device.maxR)
        if (gap === 0) break
      } else {
        device.r += (dr * budget) / gap
        device.theta += (dTheta * budget) / gap
        budget = 0
      }
    }
    device.x = device.r * Math.cos(device.theta)
    device.y = device.r * Math.sin(device.theta)
  }

  private sight(device: SimDevice, at: number): Sighting {
    const ideal = rssiAtDistance(this.distanceTo(device), { ref1m: device.ref1m, n: TRUE_EXPONENT })
    return {
      id: device.id,
      name: device.name,
      rssi: Math.round(ideal + this.gaussian() * NOISE_DB),
      txPower: device.txPower,
      observer: LOCAL_OBSERVER,
      at,
    }
  }

  /** A random [r, theta] in the annulus. */
  private pointIn(minR: number, maxR: number): [number, number] {
    return [minR + this.random() * (maxR - minR), this.random() * 2 * Math.PI]
  }

  /** Box–Muller standard normal. */
  private gaussian(): number {
    const u = 1 - this.random()
    const v = this.random()
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
  }

  /** Opaque base64-ish ids, like the ones Web Bluetooth hands out. */
  private makeId(): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let id = ''
    for (let i = 0; i < 22; i++) id += alphabet[Math.floor(this.random() * alphabet.length)]
    return `${id}==`
  }
}

/** Shortest signed turn, in (−π, π]. */
function wrapAngle(angle: number): number {
  const turn = 2 * Math.PI
  return Math.PI - ((((Math.PI - angle) % turn) + turn) % turn)
}

const TICK_MS = 100

/** Synthetic devices, so the app can be explored in any browser. */
export class DemoSource implements ScanSource {
  readonly kind = 'demo'
  private timer?: ReturnType<typeof setInterval>

  async start(emit: (sighting: Sighting) => void): Promise<void> {
    this.stop()
    const simulator = new Simulator(Date.now())
    this.timer = setInterval(() => {
      for (const sighting of simulator.advance(Date.now())) emit(sighting)
    }, TICK_MS)
  }

  stop(): void {
    if (this.timer !== undefined) clearInterval(this.timer)
    this.timer = undefined
  }
}
