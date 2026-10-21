export function formatDistance(metres: number): string {
  if (metres < 10) return `${metres.toFixed(1)} m`
  return `${Math.round(metres)} m`
}

export function formatAge(ms: number): string {
  if (ms < 1500) return 'now'
  if (ms < 60_000) return `${Math.round(ms / 1000)} s`
  return `${Math.floor(ms / 60_000)} min`
}

/** Web Bluetooth ids are long opaque strings; the first few characters are enough to tell devices apart. */
export function shortId(id: string): string {
  return id.length > 8 ? `${id.slice(0, 8)}…` : id
}

export function deviceLabel(device: { name?: string; id: string }): string {
  return device.name ?? shortId(device.id)
}
