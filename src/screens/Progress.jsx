import React, { useState, useMemo, useEffect } from 'react';
import { LineChart, BarChart, TrainingHeatmap } from '../components/Charts';
import Header from '../components/Header';
import {
  exerciseSeries,
  weeklyBuckets,
  weekStats,
  sessionVolume,
  muscleBalance,
  goalProgress,
} from '../utils/stats';
import { getAllHealth } from '../db/db';
import { getAISettings } from '../utils/storage';
import { calorieStats, latestBodyWeightKg } from '../utils/calories';

const shortDate = (iso) =>
  new Date(iso + 'T12:00:00').toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'numeric',
  });

export default function Progress({ history }) {
  const series = useMemo(() => exerciseSeries(history), [history]);
  const weeks = useMemo(() => weeklyBuckets(history, 8), [history]);
  const { thisWeek, streak } = useMemo(() => weekStats(history), [history]);
  const [exIdx, setExIdx] = useState(0);
  const [exMetric, setExMetric] = useState('w'); // w = best set weight | e = est. 1RM
  const [weekMode, setWeekMode] = useState('volume'); // volume | sessions
  const [recMode, setRecMode] = useState('hrv'); // hrv | rhr | sleep | weight
  const [healthLog, setHealthLog] = useState([]);

  // training-day heatmap: date → total volume + session count
  const heatDays = useMemo(() => {
    const m = new Map();
    for (const s of history) {
      const cur = m.get(s.date) || { volume: 0, count: 0 };
      m.set(s.date, { volume: cur.volume + sessionVolume(s), count: cur.count + 1 });
    }
    return m;
  }, [history]);
  const balance = useMemo(() => muscleBalance(history), [history]);
  const goals = useMemo(
    () => goalProgress(history, getAISettings().goals),
    [history]
  );
  const bodyKg = useMemo(() => latestBodyWeightKg(healthLog), [healthLog]);
  const calories = useMemo(() => calorieStats(history, bodyKg), [history, bodyKg]);

  useEffect(() => {
    getAllHealth().then(setHealthLog).catch(() => {});
  }, []);

  const chartable = series.filter((s) => s.points.length >= 2).slice(0, 8);
  const sel = chartable[Math.min(exIdx, chartable.length - 1)];

  const shortDay = (iso) =>
    new Date(iso + 'T12:00:00').toLocaleDateString(undefined, { day: 'numeric', month: 'numeric' });
  const recent30 = healthLog.slice(-30);
  const recPoints = (field) =>
    recent30.filter((h) => h[field]).map((h) => ({ label: shortDay(h.date), value: h[field] }));
  const REC = {
    hrv: {
      label: 'HRV',
      points: recPoints('hrv'),
      unit: 'ms',
      color: 'var(--chart-teal)',
      desc: 'Higher and steady is good.',
    },
    rhr: {
      label: 'Resting HR',
      points: recPoints('rhr'),
      unit: '',
      color: 'var(--chart-amber)',
      desc: 'Lower and steady is good.',
    },
    sleep: {
      label: 'Sleep',
      points: recPoints('sleepH'),
      unit: 'h',
      color: 'var(--chart-teal)',
      desc: 'Under ~6h, the coach eases off.',
    },
    weight: {
      label: 'Body wt',
      points: recPoints('weightKg'),
      unit: 'kg',
      color: 'var(--chart-amber)',
      desc: 'Watch the trend, not the day.',
    },
  };

  // only offer recovery modes that have enough data to chart
  const recModes = Object.entries(REC)
    .filter(([, m]) => m.points.length >= 2)
    .map(([v, m]) => [v, m.label]);
  const activeRec = recModes.some(([v]) => v === recMode)
    ? recMode
    : recModes[0]?.[0];

  return (
    <div className="screen screen--slide-in">
      <Header title="Progress" />

      {history.length < 2 && recModes.length === 0 ? (
        <div className="center-fill">
          <p className="body" style={{ color: 'var(--muted)', textAlign: 'center' }}>
            Log two sessions to unlock charts.
          </p>
        </div>
      ) : (
        <>
          {history.length >= 2 && (
          <>
          <div className="stat-row">
            <div className="stat-tile">
              <div className="stat-tile__label">This week</div>
              <div className="stat-tile__value">{thisWeek} <span className="stat-tile__unit">sessions</span></div>
            </div>
            <div className="stat-tile">
              <div className="stat-tile__label">Streak</div>
              <div className="stat-tile__value">{streak} <span className="stat-tile__unit">wks</span></div>
            </div>
            <div className="stat-tile">
              <div className="stat-tile__label">Burned</div>
              <div className="stat-tile__value">{calories.thisWeek.toLocaleString()} <span className="stat-tile__unit">kcal</span></div>
            </div>
          </div>

          <div className="card">
            <div className="card__label">Training days</div>
            <TrainingHeatmap days={heatDays} />
          </div>

          {chartable.length > 0 && sel && (() => {
            const e1Points = sel.points.filter((p) => p.e != null);
            const showE1 = e1Points.length >= 2;
            const metric = exMetric === 'e' && showE1 ? 'e' : 'w';
            const points =
              metric === 'e'
                ? e1Points.map((p) => ({ label: shortDate(p.date), value: p.e }))
                : sel.points.map((p) => ({ label: shortDate(p.date), value: p.w }));
            return (
            <div className="card">
              <div className="row-between" style={{ alignItems: 'center', marginBottom: 10 }}>
                <div className="card__label" style={{ marginBottom: 0 }}>
                  Lift trend
                </div>
                {showE1 && (
                  <div style={{ display: 'flex', gap: 6 }}>
                    {[
                      ['w', 'Weight'],
                      ['e', 'e1RM'],
                    ].map(([v, l]) => (
                      <button
                        key={v}
                        className={'chip' + (metric === v ? ' chip-on' : '')}
                        onClick={() => setExMetric(v)}
                      >
                        {l}
                      </button>
                    ))}
                  </div>
                )}
              </div>
              <div className="chip-row">
                {chartable.map((s, i) => (
                  <button
                    key={s.name}
                    className={'chip' + (s === sel ? ' chip-on' : '')}
                    onClick={() => setExIdx(i)}
                  >
                    {s.name}
                  </button>
                ))}
              </div>
              <LineChart points={points} unit="kg" />
            </div>
            );
          })()}

          <div className="card">
            <div className="row-between" style={{ alignItems: 'center', marginBottom: 10 }}>
              <div className="card__label" style={{ marginBottom: 0 }}>Weekly training</div>
              <div style={{ display: 'flex', gap: 6 }}>
                {[
                  ['volume', 'Volume'],
                  ['sessions', 'Sessions'],
                ].map(([v, l]) => (
                  <button
                    key={v}
                    className={'chip' + (weekMode === v ? ' chip-on' : '')}
                    onClick={() => setWeekMode(v)}
                  >
                    {l}
                  </button>
                ))}
              </div>
            </div>
            {weekMode === 'volume' ? (
              <BarChart
                bars={weeks.map((w) => ({ label: shortDate(w.start), value: w.volume }))}
                unit="kg"
              />
            ) : (
              <BarChart
                bars={weeks.map((w) => ({ label: shortDate(w.start), value: w.count }))}
                color="var(--chart-amber)"
              />
            )}
          </div>

          {balance.length > 0 && (
            <div className="card">
              <div className="card__label">Muscle balance · 14 days</div>
              {(() => {
                const max = Math.max(...balance.map((b) => b.sets), 1);
                return balance.map((b) => {
                  const gap = b.lastDaysAgo != null && b.lastDaysAgo >= 10;
                  return (
                    <div key={b.group} className="balance-row">
                      <span className="balance-row__name">{b.group}</span>
                      <div className="balance-row__track">
                        <div
                          className={'balance-row__fill' + (gap ? ' balance-row__fill--gap' : '')}
                          style={{ width: `${Math.max((b.sets / max) * 100, b.sets ? 6 : 0)}%` }}
                        />
                      </div>
                      <span className={'mono balance-row__meta' + (gap ? ' balance-row__meta--gap' : '')}>
                        {b.sets ? `${b.sets} sets` : `${b.lastDaysAgo}d ago`}
                      </span>
                    </div>
                  );
                });
              })()}
            </div>
          )}

          {goals.length > 0 && (
            <div className="card">
              <div className="card__label">Goals</div>
              {goals.map((g, i) => (
                <div key={i} style={{ marginTop: i ? 12 : 0 }}>
                  <div className="row-between">
                    <span className="body" style={{ fontSize: 14 }}>{g.text}</span>
                    {g.target != null && (
                      <span className="mono" style={{ fontSize: 12.5, color: 'var(--muted)' }}>
                        {g.current} / {g.target}{g.unit}
                      </span>
                    )}
                  </div>
                  {g.target != null && (
                    <div className="goal-track">
                      <div
                        className={'goal-fill' + (g.current >= g.target ? ' goal-fill--done' : '')}
                        style={{ width: `${Math.min((g.current / g.target) * 100, 100)}%` }}
                      />
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
          </>
          )}

          {recModes.length > 0 && (
            <div className="card">
              <div className="row-between" style={{ alignItems: 'center', marginBottom: 10 }}>
                <div className="card__label" style={{ marginBottom: 0 }}>Recovery</div>
                <div style={{ display: 'flex', gap: 6 }}>
                  {recModes.map(([v, l]) => (
                    <button
                      key={v}
                      className={'chip' + (activeRec === v ? ' chip-on' : '')}
                      onClick={() => setRecMode(v)}
                    >
                      {l}
                    </button>
                  ))}
                </div>
              </div>
              <LineChart
                points={REC[activeRec].points}
                unit={REC[activeRec].unit}
                color={REC[activeRec].color}
              />
              <p className="card__detail">{REC[activeRec].desc}</p>
            </div>
          )}

          {recModes.length === 0 && (
            <div className="foot-note">
              Recovery charts appear after two days of Health data.
            </div>
          )}

        </>
      )}
    </div>
  );
}
