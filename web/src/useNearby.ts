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
  const sourceRef = useRef<ScanSource | null>(null)

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

  /** Replace the running source. Call from the click handler: Bluetooth needs the user gesture. */
  const start = useCallback(
    async (source: ScanSource) => {
      stop()
      setError(null)
      sourceRef.current = source
      setKind(source.kind)
      try {
        await source.start((sighting) => tracker.ingest(sighting))
      } catch (err) {
        if (sourceRef.current === source) stop()
        setError(describeError(err))
      }
    },
    [stop, tracker],
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
      if (!isChooserCancelled(err)) setError(describeError(err))
    }
  }, [start])

  const clear = useCallback(() => {
    tracker.clear()
    setDevices([])
  }, [tracker])

  return { devices, now, kind, error, start, stop, addDevice, clear }
}
