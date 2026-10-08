import React, { useState } from 'react';
import Pill from '../components/Pill';
import Seg from '../components/Seg';
import ReadinessBar from '../components/ReadinessBar';
import Header from '../components/Header';
import Icon from '../components/Icon';
import { quickReadiness } from '../utils/helpers';
import { storeTodaysHealth } from '../utils/healthIngest';

export default function CheckIn({ ci, setCi, error, muscleGap, onCancel, onSubmit }) {
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
      <Header title="Check-in" onBack={onCancel} />

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

      <div className="q-label">Sleep</div>
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
          placeholder="Where?"
          value={ci.soreAreas}
          onChange={(e) => set({ soreAreas: e.target.value })}
        />
      )}

      <div className="q-label">Gym time</div>
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
        <span>{showMore ? 'Fewer details' : 'More details'}</span>
        <span className={'chevron' + (showMore ? ' chevron--open' : '')}><Icon name="down" size={18} /></span>
      </button>

      {showMore && (
        <div style={{ paddingTop: 4 }}>
          <Pill
            on={ci.backTight}
            warn
            style={{ marginBottom: 0 }}
            onClick={() => set({ backTight: !ci.backTight })}
          >
            {ci.backTight ? '✓ Lower back tight' : 'Lower back tight?'}
          </Pill>

          {muscleGap && (
            <Pill
              on={!!ci.prioritizeMuscle}
              style={{ marginBottom: 0, marginTop: 10 }}
              onClick={() => set({ prioritizeMuscle: ci.prioritizeMuscle ? '' : muscleGap.group })}
            >
              {ci.prioritizeMuscle
                ? `✓ Prioritizing ${muscleGap.group.toLowerCase()}`
                : `Prioritize ${muscleGap.group.toLowerCase()}? ${muscleGap.lastDaysAgo} days since last trained`}
            </Pill>
          )}

          <div className="q-label" style={{ marginTop: 18 }}>Focus</div>
          <div className="seg-group seg-group--wrap">
            {[
              ['', "Coach's call"],
              ['lift', 'Lift'],
              ['cardio', 'Cardio'],
              ['core', 'Core'],
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

          <div className="q-label q-label--row" style={{ marginTop: 18, alignItems: 'center' }}>
            <span>Health data</span>
            <button className="chip" onClick={pasteHealth}>Paste</button>
          </div>
          {autoFilled && ci.health && (
            <p style={{ fontSize: 13, color: 'var(--green)', margin: '0 0 8px' }}>Loaded from Watch</p>
          )}
          <textarea
            className="input textarea"
            style={{ marginTop: 0, minHeight: 72 }}
            placeholder="Sleep, HRV, resting HR…"
            value={ci.health}
            onChange={(e) => set({ health: e.target.value })}
          />
          <div className="q-label" style={{ marginTop: 18 }}>Body weight</div>
          <input
            className="input"
            inputMode="decimal"
            placeholder="kg"
            value={ci.bodyKg || ''}
            onChange={(e) => set({ bodyKg: e.target.value.replace(/[^\d.]/g, '').slice(0, 6) })}
            style={{ marginTop: 6 }}
          />
          <input
            className="input"
            placeholder="Anything else?"
            value={ci.notes}
            onChange={(e) => set({ notes: e.target.value })}
          />
        </div>
      )}

      <div style={{ marginTop: 24 }}>
        <ReadinessBar
          value={quickReadiness(ci)}
          label="Readiness"
        />
      </div>

      {error && <div className="err-box">{error}</div>}

      <button className="big-btn" onClick={onSubmit}>
        Build session
      </button>
      <div style={{ height: 24 }} />
    </div>
  );
}
