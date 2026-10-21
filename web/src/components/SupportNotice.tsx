import type { BluetoothSupport } from '../scan/bluetooth'

interface Props {
  support: BluetoothSupport
  /** Result of navigator.bluetooth.getAvailability(); null until known. */
  available: boolean | null
}

const FLAG = 'chrome://flags/#enable-experimental-web-platform-features'

export function SupportNotice({ support, available }: Props) {
  if (!support.secure) {
    return <p className="notice">Web Bluetooth only works on HTTPS pages (or localhost). The demo still works.</p>
  }
  if (!support.api) {
    return (
      <p className="notice">
        This browser has no Web Bluetooth. Use Chrome, Edge or Opera on desktop or Android (or Bluefy on iOS) to
        scan real devices. The demo works anywhere.
      </p>
    )
  }
  if (available === false) {
    return <p className="notice">Bluetooth looks off, or this computer has no adapter.</p>
  }
  if (!support.scan) {
    return (
      <p className="notice">
        Scanning every nearby device needs Chrome&apos;s experimental Web Bluetooth scanning: open{' '}
        <code>{FLAG}</code>, enable it and relaunch.{' '}
        {support.watch
          ? 'Until then you can add devices one at a time.'
          : 'Without it the browser cannot report signal strength, so only the demo works.'}
      </p>
    )
  }
  return null
}
