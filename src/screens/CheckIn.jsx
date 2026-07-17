import React, { useState } from 'react';
import Pill from '../components/Pill';
import Seg from '../components/Seg';
import ReadinessBar from '../components/ReadinessBar';
import { quickReadiness } from '../utils/helpers';
import { storeTodaysHealth } from '../utils/healthIngest';

export default function CheckIn({ ci, setCi, error, onCancel, onSubmit }) {
  // Auto-open the extras when the Watch Shortcut pre-filled health data
  const [autoFilled, setAutoFilled] = useState(!!ci.health);
  const [showMore, setShowMore] = useState(!!ci.health);
  const set = (patch) => setCi({ ...ci, ...patch });

  const pasteHealth = async () => {
    try {
      const text = (await navigator.clipboard.readText())?.trim().slice(0, 2000);
      if (!text) return;
      storeTodaysHealth(text);
      set({ health: text });
      setAutoFilled(true);
    } catch { /* paste declined — type it instead */ }
  };

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

      <div className="q-label q-label--row">
        <span>Energy</span>
        <span className="q-label__value">{ci.energy}/10</span>
      </div>
      <input
        type="range"
        className="slider"
        min="1"
        max="10"
        step="1"
        value={ci.energy}
        onChange={(e) => set({ energy: Number(e.target.value) })}
      />

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

      <button className="more-toggle" onClick={() => setShowMore(!showMore)}>
        <span>
          {showMore ? '− Hide more details' : '+ More details — back, vibe, health data'}
        </span>
        <span className={'chevron' + (showMore ? ' chevron--open' : '')}>⌄</span>
      </button>

      {showMore && (
        <div style={{ paddingTop: 4 }}>
          <Pill
            on={ci.backTight}
            warn
            style={{ marginBottom: 0 }}
            onClick={() => set({ backTight: !ci.backTight })}
          >
            {ci.backTight
              ? '✓ Lower back tight today — coach will adapt'
              : 'Lower back tight today?'}
          </Pill>

          <div className="q-label" style={{ marginTop: 18 }}>Today's vibe</div>
          <div className="seg-group seg-group--wrap">
            {[
              ['', "Coach's call"],
              ['lift', 'Lift'],
              ['cardio', 'Cardio'],
              ['stretch', 'Stretch'],
              ['surprise', '🎲 Surprise me'],
            ].map(([v, l]) => (
              <button
                key={v}
                className={'seg-btn' + ((ci.wish || '') === v ? ' seg-on' : '')}
                onClick={() => set({ wish: v })}
              >
                {l}
              </button>
            ))}
          </div>

          <div className="q-label" style={{ marginTop: 18 }}>Health data</div>
          {autoFilled && ci.health ? (
            <p className="mono" style={{ fontSize: 12, color: 'var(--teal)', margin: '0 0 8px' }}>
              ⌚ Watch data loaded — the coach will read it
            </p>
          ) : (
            <Pill on={false} style={{ marginBottom: 8 }} onClick={pasteHealth}>
              ⌚ Paste Watch data from clipboard
            </Pill>
          )}
          <textarea
            className="input textarea"
            style={{ marginTop: 0 }}
            placeholder={
              'Paste anything — sleep, HRV, resting HR, steps.\ne.g. Sleep 6h40m · HRV 48 · RHR 58'
            }
            value={ci.health}
            onChange={(e) => set({ health: e.target.value })}
          />
          <div className="q-label" style={{ marginTop: 18 }}>Body weight today (optional)</div>
          <input
            className="input"
            inputMode="decimal"
            placeholder="kg — one number a day, charted in Stats"
            value={ci.bodyKg || ''}
            onChange={(e) => set({ bodyKg: e.target.value.replace(/[^\d.]/g, '').slice(0, 6) })}
            style={{ marginTop: 6 }}
          />
          <input
            className="input"
            placeholder="Anything else? (injury, plans — optional)"
            value={ci.notes}
            onChange={(e) => set({ notes: e.target.value })}
          />
          <p className="foot-note" style={{ marginTop: 10 }}>
            Tip: paste today's Apple Health numbers — the coach reads them.
          </p>
        </div>
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
