import React, { useState } from 'react';
import { fmtDate } from '../utils/helpers';
import { prRecords, exerciseSeries, weekStats, sessionVolume } from '../utils/stats';
import { LineChart } from '../components/Charts';

// ── Milestone badges ─────────────────────────────────────────────
// Each ladder: [emoji, label-template, thresholds, value-extractor]
function badgeLadders(history, records) {
  const totalVolume = history.reduce((a, s) => a + sessionVolume(s), 0);
  const { streak } = weekStats(history);
  const heaviest = records.reduce((a, r) => Math.max(a, r.weight?.w || 0), 0);
  return [
    {
      emoji: '📅',
      unit: 'sessions',
      value: history.length,
      steps: [10, 25, 50, 100, 250],
    },
    {
      emoji: '🔥',
      unit: 'week streak',
      value: streak,
      steps: [2, 4, 8, 12, 26],
    },
    {
      emoji: '🏋️',
      unit: 'tonnes lifted',
      value: Math.floor(totalVolume / 1000),
      steps: [5, 10, 25, 50, 100],
    },
    {
      emoji: '🥇',
      unit: 'kg heaviest lift',
      value: heaviest,
      steps: [40, 60, 80, 100, 140],
    },
  ];
}

export default function Records({ history, onBack }) {
  const records = prRecords(history).filter((r) => r.weight);
  const series = exerciseSeries(history);
  const [openEx, setOpenEx] = useState(null); // exercise name or null
  const totalVolume = history.reduce((a, s) => a + sessionVolume(s), 0);
  const { streak } = weekStats(history);

  const ladders = badgeLadders(history, records);

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="brand-sm">🏆 RECORDS</div>
        <div />
      </header>

      <div className="stat-row">
        <div className="stat-tile">
          <div className="stat-tile__label">Sessions</div>
          <div className="stat-tile__value">{history.length}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile__label">Lifted lifetime</div>
          <div className="stat-tile__value">
            {totalVolume >= 10000
              ? `${Math.round(totalVolume / 1000)}`
              : (totalVolume / 1000).toFixed(1)}
            <span className="stat-tile__unit">t</span>
          </div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile__label">Week streak</div>
          <div className="stat-tile__value">{streak}</div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <div className="card__label">Milestones</div>
        <div className="badge-grid">
          {ladders.map((l) => {
            const earned = l.steps.filter((s) => l.value >= s);
            const next = l.steps.find((s) => l.value < s);
            return (
              <React.Fragment key={l.unit}>
                {earned.map((s) => (
                  <div key={s} className="badge badge--earned">
                    <span className="badge__emoji">{l.emoji}</span>
                    <span className="badge__text">{s} {l.unit}</span>
                  </div>
                ))}
                {next && (
                  <div className="badge">
                    <span className="badge__emoji">{l.emoji}</span>
                    <span className="badge__text">
                      {next} {l.unit}
                      <span className="badge__progress"> · {l.value}/{next}</span>
                    </span>
                  </div>
                )}
              </React.Fragment>
            );
          })}
        </div>
      </div>

      <div className="card">
        <div className="card__label">Personal records</div>
        {records.length === 0 && (
          <p className="body" style={{ color: 'var(--muted)' }}>
            Log some weighted sets and your records will appear here.
          </p>
        )}
        {records.map((r) => {
          const isOpen = openEx === r.name;
          const pts = series.find((e) => e.name === r.name)?.points || [];
          return (
            <div key={r.name} className="pr-row" onClick={() => setOpenEx(isOpen ? null : r.name)}>
              <div className="row-between">
                <span className="body" style={{ fontWeight: 600 }}>{r.name}</span>
                <span className="mono" style={{ color: 'var(--amber)' }}>
                  {r.weight.w}kg × {r.weight.reps || '?'}
                </span>
              </div>
              <div className="mono pr-row__detail">
                {fmtDate(r.weight.date)} · {r.count} sets logged
                {r.e1rm ? ` · est. 1RM ${r.e1rm.v}kg` : ''}
                <span style={{ float: 'right', color: 'var(--dim)' }}>{isOpen ? '▾' : '▸'}</span>
              </div>
              {isOpen && pts.length >= 2 && (
                <div style={{ marginTop: 8 }} onClick={(e) => e.stopPropagation()}>
                  <LineChart
                    points={pts.map((p) => ({ label: p.date, value: p.e || p.w }))}
                    unit="kg"
                  />
                  <p className="mono" style={{ fontSize: 11.5, color: 'var(--dim)', marginTop: 4 }}>
                    est. 1RM per session, first → latest
                  </p>
                </div>
              )}
              {isOpen && pts.length < 2 && (
                <p className="mono" style={{ fontSize: 12, color: 'var(--dim)', marginTop: 6 }}>
                  Train it once more to unlock the trend chart.
                </p>
              )}
            </div>
          );
        })}
      </div>
      <div style={{ height: 24 }} />
    </div>
  );
}
