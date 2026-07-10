import React from 'react';

export default function ReadinessBar({ value, label }) {
  const segs = 20;
  const filled = Math.round((value / 100) * segs);
  const color = value >= 70 ? '#39D0B8' : value >= 45 ? '#F5A623' : '#F26D5B';

  return (
    <div className="readiness-bar">
      <div className="readiness-bar__header">
        <span className="readiness-bar__label">{label}</span>
        <span className="readiness-bar__value" style={{ color }}>
          {value}
        </span>
      </div>
      <div className="readiness-bar__track">
        {Array.from({ length: segs }, (_, i) => (
          <div
            key={i}
            className="readiness-bar__seg"
            style={{
              background: i < filled ? color : '#232B3A',
              opacity: i < filled ? 0.5 + 0.5 * (i / segs) : 1,
            }}
          />
        ))}
      </div>
    </div>
  );
}
