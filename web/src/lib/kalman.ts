/**
 * Scalar Kalman filter for a slowly drifting signal such as RSSI in dB.
 * Process noise accrues with elapsed time, so irregular advertising intervals are handled.
 */
export class Kalman1D {
  private x = Number.NaN
  private p = 0
  private lastAt = 0

  /**
   * @param q process noise, dB² per second: how fast the true value may drift
   * @param r measurement noise, dB²: variance of a single reading
   */
  constructor(
    public q: number,
    public r: number,
  ) {}

  get value(): number {
    return this.x
  }

  update(z: number, at: number): number {
    if (Number.isNaN(this.x)) {
      this.x = z
      this.p = this.r
      this.lastAt = at
      return z
    }
    const dt = Math.max(0, (at - this.lastAt) / 1000)
    this.lastAt = at
    const prior = this.p + this.q * dt
    const gain = prior / (prior + this.r)
    this.x += gain * (z - this.x)
    this.p = (1 - gain) * prior
    return this.x
  }
}
