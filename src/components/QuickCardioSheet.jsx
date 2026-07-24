import React, { useState } from 'react';
import ActionSheet from './ActionSheet';
import { cleanTime, cleanDist } from '../utils/helpers';

// Bypasses check-in + AI entirely: a run/ride/walk logged straight to
// history in a few taps, from Home. Kept separate from the generated
// strength plan — doing cardio never touches today's AI session.
const META = {
  run: { label: 'Log a run', verb: 'run', icon: '🏃' },
  cycle: { label: 'Log a ride', verb: 'ride', icon: '🚴' },
  walk: { label: 'Log a walk', verb: 'walk', icon: '🚶' },
};

export default function QuickCardioSheet({ kind, onClose, onSave }) {
  const meta = META[kind] || META.run;
  const [time, setTime] = useState('');
  const [dist, setDist] = useState('');
  const [rpe, setRpe] = useState(6);
  const canSave = !!(time || dist);

  const save = () => {
    if (!canSave) return;
    onSave(kind, { time, dist, rpe });
    onClose();
  };

  return (
    <ActionSheet title={meta.label} onClose={onClose}>
      <p className="action-sheet__note">
        Saved straight to your log — no check-in, no AI plan.
      </p>
      <div className="set-row" style={{ marginTop: 14 }}>
        <input
          className="set-input"
          inputMode="decimal"
          placeholder="min"
          value={time}
          autoFocus
          onChange={(e) => setTime(cleanTime(e.target.value))}
        />
        <span className="set-x">min</span>
        <input
          className="set-input"
          inputMode="decimal"
          placeholder="km"
          value={dist}
          onChange={(e) => setDist(cleanDist(e.target.value))}
        />
        <span className="set-x">km (optional)</span>
      </div>
      <div className="q-label q-label--row" style={{ marginTop: 18 }}>
        <span>Effort</span>
        <span className="q-label__value">{rpe}/10</span>
      </div>
      <input
        type="range"
        className="slider"
        min="1"
        max="10"
        step="1"
        value={rpe}
        onChange={(e) => setRpe(Number(e.target.value))}
      />
      <button className="action-sheet__go" disabled={!canSave} onClick={save}>
        {meta.icon} Save {meta.verb}
      </button>
    </ActionSheet>
  );
}
