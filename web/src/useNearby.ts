import { useCallback, useEffect, useRef, useState } from 'react'
import type { Settings } from './lib/settings'
import { Tracker, type TrackedDevice } from './lib/tracker'
import { describeError, isChooserCancelled, WatchSource } from './scan/bluetooth'
import type { ScanSource, SourceKind } from './scan/types'

/** How often the UI takes a snapshot of the tracker. */
const SNAPSHOT_MS = 250

export function useNearby(settings: Settings) {
  const [tracker] = useState(() => new Tracker(settings))
  const [devices, setDevices] = useState<TrackedDevice[]>([])
  const [now, setNow] = useState(() => Date.now())
  const [kind, setKind] = useState<SourceKind | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const sourceRef = useRef<ScanSource | null>(null)
  /** Whether the tracker holds synthetic devices, so they never mix with real ones. */
  const holdsDemoRef = useRef(false)

  useEffect(() => {
    tracker.configure(settings)
  }, [tracker, settings])

  useEffect(() => {
    const timer = setInterval(() => {
      const at = Date.now()
      tracker.prune(at)
      setDevices(tracker.devices())
      setNow(at)
    }, SNAPSHOT_MS)
    return () => clearInterval(timer)
  }, [tracker])

  const stop = useCallback(() => {
    sourceRef.current?.stop()
    sourceRef.current = null
    setKind(null)
  }, [])

  useEffect(() => stop, [stop])

  const clear = useCallback(() => {
    tracker.clear()
    setDevices([])
  }, [tracker])

  // Browsers end LE scans while the page is hidden, and restarting one needs a user gesture.
  useEffect(() => {
    const onVisibilityChange = () => {
      if (document.visibilityState !== 'hidden' || sourceRef.current?.kind !== 'scan') return
      stop()
      setNotice('Scanning paused while the page was hidden. Press Scan to resume.')
    }
    document.addEventListener('visibilitychange', onVisibilityChange)
    return () => document.removeEventListener('visibilitychange', onVisibilityChange)
  }, [stop])

  /** Replace the running source. Call from the click handler: Bluetooth needs the user gesture. */
  const start = useCallback(
    async (source: ScanSource) => {
      stop()
      setError(null)
      setNotice(null)
      const demo = source.kind === 'demo'
      if (holdsDemoRef.current !== demo) clear()
      holdsDemoRef.current = demo
      sourceRef.current = source
      setKind(source.kind)
      try {
        await source.start((sighting) => tracker.ingest(sighting))
      } catch (err) {
        // A source that was stopped or replaced meanwhile has nothing left to report.
        if (sourceRef.current !== source) return
        stop()
        setError(describeError(err))
      }
    },
    [clear, stop, tracker],
  )

  /** Pick one more device in the browser's chooser and follow its advertisements. */
  const addDevice = useCallback(async () => {
    let source = sourceRef.current
    if (!(source instanceof WatchSource)) {
      source = new WatchSource()
      await start(source)
    }
    try {
      await (source as WatchSource).add()
    } catch (err) {
      if (sourceRef.current === source && !isChooserCancelled(err)) setError(describeError(err))
    }
  }, [start])

  return { devices, now, kind, error, notice, start, stop, addDevice, clear }
}
