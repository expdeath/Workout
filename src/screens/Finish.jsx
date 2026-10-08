import React, { useEffect, useMemo, useState } from 'react';
import Header from '../components/Header';

const CONFETTI_COLORS = ['#F5A623', '#39D0B8', '#F26D5B', '#7EA6F5', '#E4C1F9'];

export default function Finish({ fin, setFin, prs = [], onSave, onBack }) {
  // PR celebration: one confetti burst + a buzz when the screen opens
  const [confetti, setConfetti] = useState(prs.length > 0);
  const pieces = useMemo(
    () =>
      Array.from({ length: 28 }, (_, i) => ({
        left: `${(i * 37 + 13) % 100}%`,
        background: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
        animationDelay: `${(i % 7) * 0.12}s`,
        animationDuration: `${2 + ((i * 13) % 10) / 10}s`,
      })),
    []
  );
  useEffect(() => {
    if (!confetti) return;
    try {
      navigator.vibrate?.([100, 60, 100, 60, 200]);
    } catch { /* no haptics */ }
    const t = setTimeout(() => setConfetti(false), 3200);
    return () => clearTimeout(t);
  }, [confetti]);

  return (
    <div className="screen screen--slide-in">
      {confetti && (
        <div className="confetti-burst" aria-hidden="true">
          {pieces.map((s, i) => (
            <span key={i} style={s} />
          ))}
        </div>
      )}
      <Header title="How did it go?" onBack={onBack} />

      {prs.length > 0 && (
        <div className="pr-banner">
          <div className="pr-banner__title">🏆 New record{prs.length > 1 ? 's' : ''}</div>
          {prs.map((p) => (
            <div key={p.name + p.kind} className="pr-banner__row">
              {p.name} · {p.kind === 'weight' ? '' : 'e1RM '}{p.from} → {p.to}kg
            </div>
          ))}
        </div>
      )}

      <div className="q-label q-label--row" style={{ marginTop: 0 }}>
        <span>Effort (RPE)</span>
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

      <div className="q-label">Any pain?</div>
      <input
        className="input"
        style={{ marginTop: 0 }}
        placeholder="None"
        value={fin.pain}
        onChange={(e) => setFin({ ...fin, pain: e.target.value })}
      />

      <div className="q-label">Too easy or too hard?</div>
      <input
        className="input"
        style={{ marginTop: 0 }}
        placeholder="e.g. curls felt brutal"
        value={fin.feedback}
        onChange={(e) => setFin({ ...fin, feedback: e.target.value })}
      />

      <button className="big-btn" onClick={onSave} style={{ marginTop: 28 }}>
        Save session
      </button>
    </div>
  );
}
