import React from 'react';

export default function Finish({ fin, setFin, onSave, onBack }) {
  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Back</button>
        <div />
      </header>
      <h2 className="h2">Log it. 20 seconds.</h2>

      <div className="card__label">Overall session RPE</div>
      <div className="energy-row">
        {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => (
          <button
            key={n}
            className={'num-btn' + (fin.rpe === n ? ' num-on' : '')}
            onClick={() => setFin({ ...fin, rpe: n })}
          >
            {n}
          </button>
        ))}
      </div>

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
