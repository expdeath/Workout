import React, { useState } from 'react';
import Pill from '../components/Pill';
import Seg from '../components/Seg';
import ReadinessBar from '../components/ReadinessBar';
import { quickReadiness } from '../utils/helpers';

export default function CheckIn({ ci, setCi, error, onCancel, onSubmit }) {
  // Auto-open the health section when the Watch Shortcut pre-filled it
  const [autoFilled] = useState(!!ci.health);
  const [showHealth, setShowHealth] = useState(!!ci.health);
  const set = (patch) => setCi({ ...ci, ...patch });

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onCancel}>Cancel</button>
        <div className="brand-sm">CHECK-IN</div>
        <div />
      </header>

      <p className="subtitle" style={{ marginTop: 0 }}>
        Pre-set for a normal day. Only tap what's different — then build.
      </p>

      <div className="q-label">Energy</div>
      <div className="energy-row">
        {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => (
          <button
            key={n}
            className={'num-btn' + (ci.energy === n ? ' num-on' : '')}
            onClick={() => set({ energy: n })}
          >
            {n}
          </button>
        ))}
      </div>

      <div className="q-label">Sleep last night</div>
      <Seg
        options={[
          ['Great', 'Great'],
          ['OK', 'OK'],
          ['Poor', 'Poor'],
        ]}
        value={ci.sleep}
        onChange={(v) => set({ sleep: v })}
      />

      <div className="q-label">Soreness</div>
      <Seg
        options={[
          ['None', 'None'],
          ['Light', 'Light'],
          ['Very sore', 'Very sore'],
        ]}
        value={ci.soreness}
        onChange={(v) => set({ soreness: v })}
      />
      {ci.soreness !== 'None' && (
        <input
          className="input"
          placeholder="Where? e.g. chest, quads"
          value={ci.soreAreas}
          onChange={(e) => set({ soreAreas: e.target.value })}
        />
      )}
      <Pill
        on={ci.backTight}
        warn
        style={{ marginTop: 10, marginBottom: 0 }}
        onClick={() => set({ backTight: !ci.backTight })}
      >
        {ci.backTight
          ? '✓ Lower back tight today — coach will adapt'
          : 'Lower back tight today?'}
      </Pill>

      <div className="q-label">Gym time (walk not included)</div>
      <Seg
        options={[
          ['30', '30m'],
          ['45', '45m'],
          ['60', '60m'],
          ['75', '75m+'],
        ]}
        value={ci.timeAvail}
        onChange={(v) => set({ timeAvail: v })}
      />

      <button
        className="ghost-btn"
        style={{ marginTop: 22, padding: 0 }}
        onClick={() => setShowHealth(!showHealth)}
      >
        {showHealth
          ? '− Hide health data'
          : '+ Paste Apple Health data (optional)'}
      </button>
      {showHealth && (
        <>
          {autoFilled && (
            <p className="mono" style={{ fontSize: 12, color: 'var(--teal)', margin: '6px 0 0' }}>
              ⌚ Received from your Apple Watch shortcut today
            </p>
          )}
          <button
            className="ghost-btn"
            style={{ display: 'block', padding: '4px 0', color: 'var(--teal)' }}
            onClick={async () => {
              try {
                const text = await navigator.clipboard.readText();
                if (text) set({ health: text.slice(0, 2000) });
              } catch {
                /* clipboard permission denied — user can paste manually */
              }
            }}
          >
            ⎘ Paste from clipboard
          </button>
          <textarea
            className="input textarea"
            placeholder={
              'Paste anything — sleep, HRV, resting HR, steps.\ne.g. Sleep 6h40m · HRV 48 · RHR 58'
            }
            value={ci.health}
            onChange={(e) => set({ health: e.target.value })}
          />
          <input
            className="input"
            placeholder="Anything else? (injury, plans — optional)"
            value={ci.notes}
            onChange={(e) => set({ notes: e.target.value })}
          />
        </>
      )}

      <div style={{ marginTop: 24 }}>
        <ReadinessBar
          value={quickReadiness(ci)}
          label="Quick readiness estimate"
        />
      </div>

      {error && <div className="err-box">{error}</div>}

      <button className="big-btn" onClick={onSubmit}>
        Build today's session
      </button>
      <div style={{ height: 24 }} />
    </div>
  );
}
