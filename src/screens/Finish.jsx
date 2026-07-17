import React from 'react';

export default function Finish({ fin, setFin, prs = [], onSave, onBack }) {
  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Back</button>
        <div />
      </header>
      <h2 className="h2">Log it. 20 seconds.</h2>

      {prs.length > 0 && (
        <div className="pr-banner">
          <div className="pr-banner__title">🏆 New personal record{prs.length > 1 ? 's' : ''}</div>
          {prs.map((p) => (
            <div key={p.name + p.kind} className="mono pr-banner__row">
              {p.name} —{' '}
              {p.kind === 'weight'
                ? `heaviest set ${p.from} → ${p.to}kg`
                : `est. 1RM ${p.from} → ${p.to}kg`}
            </div>
          ))}
        </div>
      )}

      <div className="q-label q-label--row" style={{ marginTop: 0 }}>
        <span>Overall session RPE</span>
        <span className="q-label__value">{fin.rpe}/10</span>
      </div>
      <input
        type="range"
        className="slider"
        min="1"
        max="10"
        step="1"
        value={fin.rpe}
        onChange={(e) => setFin({ ...fin, rpe: Number(e.target.value) })}
      />

      <div className="card__label" style={{ marginTop: 20 }}>
        Any pain or discomfort?
      </div>
      <input
        className="input"
        placeholder="e.g. none / left shoulder on incline press"
        value={fin.pain}
        onChange={(e) => setFin({ ...fin, pain: e.target.value })}
      />

      <div className="card__label" style={{ marginTop: 20 }}>
        Too easy / too hard?
      </div>
      <input
        className="input"
        placeholder="e.g. leg press felt light, curls brutal"
        value={fin.feedback}
        onChange={(e) => setFin({ ...fin, feedback: e.target.value })}
      />

      <button className="big-btn" onClick={onSave} style={{ marginTop: 28 }}>
        Save session
      </button>
      <p className="foot-note">
        Weights and reps you logged per set are saved automatically. This feeds
        tomorrow's plan.
      </p>
    </div>
  );
}
