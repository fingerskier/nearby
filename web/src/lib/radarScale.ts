/** Range rings, metres. The radar's outer edge is always one of these. */
export const RINGS = [1, 2, 5, 10, 20, 50, 100]

const MIN_RANGE = 2

/**
 * Outer range for the radar: grows as soon as a device falls outside it, but only shrinks once
 * everything fits well inside the next ring down, so the scale doesn't flicker with noisy estimates.
 */
export function nextRange(current: number, farthest: number): number {
  const fit = RINGS.find((ring) => ring >= Math.max(MIN_RANGE, farthest)) ?? RINGS[RINGS.length - 1]
  if (fit >= current) return fit
  const below = RINGS.filter((ring) => ring < current).pop() ?? fit
  return farthest < below * 0.8 ? Math.max(fit, below) : current
}

/** Logarithmic radius, so near devices stay apart while far ones still fit on screen. */
export function radiusFor(distance: number, range: number, outerPx: number): number {
  return (outerPx * Math.log1p(Math.min(distance, range))) / Math.log1p(range)
}
