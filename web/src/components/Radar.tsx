import { useEffect, useRef, useState, type MouseEvent } from 'react'
import { deviceLabel, formatDistance } from '../lib/format'
import { nextRange, radiusFor, RINGS } from '../lib/radarScale'
import type { TrackedDevice } from '../lib/tracker'

interface Props {
  devices: TrackedDevice[]
  now: number
  staleMs: number
  selected: string | null
  onSelect: (id: string | null) => void
}

interface Placed {
  device: TrackedDevice
  x: number
  y: number
}

const PADDING = 28
const DOT = 5
const HIT_RADIUS = 18
const MAX_LABELS = 12

export function Radar({ devices, now, staleMs, selected, onSelect }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const rangeRef = useRef(5)
  const placedRef = useRef<Placed[]>([])
  const [size, setSize] = useState(0)

  useEffect(() => {
    const wrap = wrapRef.current
    if (!wrap) return
    const observer = new ResizeObserver(([entry]) => setSize(Math.floor(entry.contentRect.width)))
    observer.observe(wrap)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    if (!canvas || !ctx || size === 0) return

    const dpr = window.devicePixelRatio || 1
    canvas.width = Math.round(size * dpr)
    canvas.height = Math.round(size * dpr)
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, size, size)

    const style = getComputedStyle(canvas)
    const color = (name: string) => style.getPropertyValue(name).trim()
    const farthest = devices.reduce((max, device) => Math.max(max, device.distance), 0)
    const range = (rangeRef.current = nextRange(rangeRef.current, farthest))
    const centre = size / 2
    const outer = centre - PADDING

    ctx.font = '11px system-ui, sans-serif'
    ctx.lineWidth = 1
    ctx.strokeStyle = color('--ring')
    ctx.beginPath()
    ctx.moveTo(centre - outer, centre)
    ctx.lineTo(centre + outer, centre)
    ctx.moveTo(centre, centre - outer)
    ctx.lineTo(centre, centre + outer)
    ctx.stroke()

    ctx.textAlign = 'center'
    ctx.textBaseline = 'bottom'
    for (const ring of RINGS) {
      if (ring > range) break
      const r = radiusFor(ring, range, outer)
      ctx.strokeStyle = color('--ring')
      ctx.beginPath()
      ctx.arc(centre, centre, r, 0, 2 * Math.PI)
      ctx.stroke()
      ctx.fillStyle = color('--muted')
      ctx.fillText(`${ring} m`, centre + 14, centre - r - 2)
    }

    ctx.fillStyle = color('--accent')
    ctx.beginPath()
    ctx.arc(centre, centre, 4, 0, 2 * Math.PI)
    ctx.fill()

    const placed = devices.map((device) => {
      const r = radiusFor(device.distance, range, outer)
      return { device, x: centre + r * Math.cos(device.angle), y: centre + r * Math.sin(device.angle) }
    })
    placedRef.current = placed
    // Draw the selected device last so it sits on top.
    const ordered = [...placed].sort((a, b) => Number(a.device.id === selected) - Number(b.device.id === selected))

    ctx.textBaseline = 'middle'
    for (const { device, x, y } of ordered) {
      const isSelected = device.id === selected
      ctx.globalAlpha = 1 - Math.min(0.75, (now - device.lastSeen) / staleMs)
      ctx.fillStyle = color(device.calibrated ? '--calibrated' : '--dot')
      ctx.beginPath()
      ctx.arc(x, y, isSelected ? DOT + 2 : DOT, 0, 2 * Math.PI)
      ctx.fill()
      if (isSelected) {
        ctx.strokeStyle = color('--accent')
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(x, y, DOT + 6, 0, 2 * Math.PI)
        ctx.stroke()
        ctx.lineWidth = 1
      }
      if (isSelected || placed.length <= MAX_LABELS) {
        // Label toward the centre so it never runs off the canvas edge.
        const left = x < centre
        const labelX = x + (left ? 10 : -10)
        const text = isSelected ? `${deviceLabel(device)} · ${formatDistance(device.distance)}` : deviceLabel(device)
        ctx.textAlign = left ? 'left' : 'right'
        // A halo in the panel colour keeps overlapping labels legible.
        ctx.strokeStyle = color('--panel')
        ctx.lineWidth = 3
        ctx.lineJoin = 'round'
        ctx.strokeText(text, labelX, y)
        ctx.lineWidth = 1
        ctx.fillStyle = color('--text')
        ctx.fillText(text, labelX, y)
      }
    }
    ctx.globalAlpha = 1
  }, [devices, now, staleMs, selected, size])

  function handleClick(event: MouseEvent<HTMLCanvasElement>) {
    const rect = event.currentTarget.getBoundingClientRect()
    const x = event.clientX - rect.left
    const y = event.clientY - rect.top
    let hit: Placed | null = null
    let best = HIT_RADIUS
    for (const placed of placedRef.current) {
      const gap = Math.hypot(placed.x - x, placed.y - y)
      if (gap < best) {
        hit = placed
        best = gap
      }
    }
    onSelect(hit ? hit.device.id : null)
  }

  const nearest = devices[0]
  const summary = nearest
    ? `${devices.length} devices; nearest ${deviceLabel(nearest)} at about ${formatDistance(nearest.distance)}`
    : 'No devices'

  return (
    <div className="radar" ref={wrapRef}>
      <canvas ref={canvasRef} role="img" aria-label={`Radar: ${summary}`} onClick={handleClick} />
    </div>
  )
}
