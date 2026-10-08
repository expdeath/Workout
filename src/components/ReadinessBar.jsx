import React from 'react';

// One thin bar — teal ≥70, amber ≥45, red below; the number carries the meaning.
export default function ReadinessBar({ value, label }) {
  const color = value >= 70 ? 'var(--green)' : value >= 45 ? 'var(--amber)' : 'var(--red)';

  return (
    <div className="readiness-bar" role="meter" aria-label={label} aria-valuenow={value} aria-valuemin={0} aria-valuemax={100}>
      <span className="readiness-bar__label">{label}</span>
      <div className="readiness-bar__track">
        <div className="readiness-bar__fill" style={{ width: `${Math.max(0, Math.min(100, value))}%`, background: color }} />
      </div>
      <span className="readiness-bar__value" style={{ color }}>{value}</span>
    </div>
  );
}
