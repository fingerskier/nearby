// @vitest-environment jsdom
import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { DEFAULT_SETTINGS } from './lib/settings'
import type { ScanSource, Sighting, SourceKind } from './scan/types'
import { useNearby } from './useNearby'

/** A source whose start() settles when the test says so, and that emits on demand. */
function fakeSource(kind: SourceKind) {
  let emit: (sighting: Sighting) => void = () => {}
  let settle: { resolve: () => void; reject: (error: unknown) => void } | undefined
  const source: ScanSource = {
    kind,
    start: vi.fn(
      (next: (sighting: Sighting) => void) =>
        new Promise<void>((resolve, reject) => {
          emit = next
          settle = { resolve, reject }
        }),
    ),
    stop: vi.fn(),
  }
  return {
    source,
    emit: (id: string) => emit({ id, rssi: -60, observer: 'local', at: Date.now() }),
    resolve: () => settle?.resolve(),
    reject: (error: unknown) => settle?.reject(error),
  }
}

function setVisibility(state: DocumentVisibilityState) {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state })
  document.dispatchEvent(new Event('visibilitychange'))
}

describe('useNearby', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => {
    vi.useRealTimers()
    setVisibility('visible')
  })

  async function startWith(hook: { current: ReturnType<typeof useNearby> }, fake: ReturnType<typeof fakeSource>) {
    let started!: Promise<void>
    act(() => {
      started = hook.current.start(fake.source)
    })
    return started
  }

  it('drops demo devices when switching to a live source', async () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const demo = fakeSource('demo')
    startWith(result, demo)
    demo.emit('synthetic')
    await act(() => vi.advanceTimersByTimeAsync(300))
    expect(result.current.devices.map((d) => d.id)).toEqual(['synthetic'])

    const live = fakeSource('scan')
    startWith(result, live)
    live.emit('real')
    await act(() => vi.advanceTimersByTimeAsync(300))
    expect(demo.source.stop).toHaveBeenCalled()
    expect(result.current.devices.map((d) => d.id)).toEqual(['real'])
  })

  it('starts each demo with a fresh world', async () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const first = fakeSource('demo')
    startWith(result, first)
    first.emit('old-world')
    const second = fakeSource('demo')
    startWith(result, second)
    second.emit('new-world')
    await act(() => vi.advanceTimersByTimeAsync(300))
    expect(result.current.devices.map((d) => d.id)).toEqual(['new-world'])
  })

  it('keeps live devices when switching between live sources', async () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const scan = fakeSource('scan')
    startWith(result, scan)
    scan.emit('real')
    const watch = fakeSource('watch')
    startWith(result, watch)
    await act(() => vi.advanceTimersByTimeAsync(300))
    expect(result.current.devices.map((d) => d.id)).toEqual(['real'])
  })

  it('ignores a failure from a source that was already replaced', async () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const scan = fakeSource('scan')
    const scanStarted = startWith(result, scan)
    const demo = fakeSource('demo')
    startWith(result, demo)
    await act(async () => {
      scan.reject(new DOMException('denied', 'NotAllowedError'))
      await scanStarted
    })
    expect(result.current.error).toBeNull()
    expect(result.current.kind).toBe('demo')
  })

  it('reports a failure from the current source', async () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const scan = fakeSource('scan')
    const started = startWith(result, scan)
    await act(async () => {
      scan.reject(new DOMException('denied', 'NotAllowedError'))
      await started
    })
    expect(result.current.error).toMatch(/permission/i)
    expect(result.current.kind).toBeNull()
  })

  it('stops an LE scan when the page is hidden and says how to resume', async () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const scan = fakeSource('scan')
    startWith(result, scan)
    act(() => setVisibility('hidden'))
    expect(scan.source.stop).toHaveBeenCalled()
    expect(result.current.kind).toBeNull()
    expect(result.current.notice).toMatch(/press scan/i)
  })

  it('leaves the demo running when the page is hidden', () => {
    const { result } = renderHook(() => useNearby(DEFAULT_SETTINGS))
    const demo = fakeSource('demo')
    startWith(result, demo)
    act(() => setVisibility('hidden'))
    expect(demo.source.stop).not.toHaveBeenCalled()
    expect(result.current.kind).toBe('demo')
  })
})
