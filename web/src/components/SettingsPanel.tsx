import { DEFAULT_SETTINGS, LIMITS, type Settings } from '../lib/settings'

interface Props {
  settings: Settings
  onChange: (settings: Settings) => void
}

interface SliderProps {
  label: string
  hint: string
  field: keyof typeof LIMITS
  unit: string
  settings: Settings
  onChange: (settings: Settings) => void
}

function Slider({ label, hint, field, unit, settings, onChange }: SliderProps) {
  const { min, max, step } = LIMITS[field]
  const id = `setting-${field}`
  return (
    <div className="field">
      <label htmlFor={id}>
        {label} <output htmlFor={id}>{`${settings[field]}${unit}`}</output>
      </label>
      <input
        id={id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={settings[field]}
        onChange={(event) => onChange({ ...settings, [field]: Number(event.target.value) })}
      />
      <small>{hint}</small>
    </div>
  )
}

export function SettingsPanel({ settings, onChange }: Props) {
  const calibrated = Object.keys(settings.calibrations).length
  return (
    <div className="settings-grid">
      <Slider
        label="Path-loss exponent"
        field="n"
        unit=""
        hint="About 2 in open space, 2.5–3 indoors, 3–4 through walls and people."
        settings={settings}
        onChange={onChange}
      />
      <Slider
        label="Signal at 1 m"
        field="ref1m"
        unit=" dBm"
        hint="Default reference for devices without calibration or advertised TX power."
        settings={settings}
        onChange={onChange}
      />
      <Slider
        label="Reading noise"
        field="noiseDb"
        unit=" dB"
        hint="Higher smooths more but reacts more slowly to movement."
        settings={settings}
        onChange={onChange}
      />
      <Slider
        label="Forget after"
        field="staleSeconds"
        unit=" s"
        hint="Devices silent this long are removed."
        settings={settings}
        onChange={onChange}
      />
      <div className="field">
        <label>
          <input
            type="checkbox"
            checked={settings.useTxPower}
            onChange={(event) => onChange({ ...settings, useTxPower: event.target.checked })}
          />{' '}
          Use advertised TX power
        </label>
        <small>When a device announces its transmit power, derive its 1 m reference from it.</small>
      </div>
      <div className="field actions">
        <button type="button" onClick={() => onChange({ ...DEFAULT_SETTINGS, calibrations: settings.calibrations })}>
          Reset to defaults
        </button>
        <button
          type="button"
          disabled={calibrated === 0}
          onClick={() => onChange({ ...settings, calibrations: {} })}
        >
          Clear {calibrated} calibration{calibrated === 1 ? '' : 's'}
        </button>
      </div>
    </div>
  )
}
