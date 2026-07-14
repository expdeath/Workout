import React, { useState, useMemo, useEffect } from 'react';
import { LineChart, BarChart } from '../components/Charts';
import { exerciseSeries, weeklyBuckets, weekStats } from '../utils/stats';
import { getAllHealth } from '../db/db';
import { fmtDate } from '../utils/helpers';

const shortDate = (iso) =>
  new Date(iso + 'T12:00:00').toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'numeric',
  });

export default function Progress({ history, onBack }) {
  const series = useMemo(() => exerciseSeries(history), [history]);
  const weeks = useMemo(() => weeklyBuckets(history, 8), [history]);
  const { thisWeek, streak } = useMemo(() => weekStats(history), [history]);
  const [exIdx, setExIdx] = useState(0);
  const [weekMode, setWeekMode] = useState('volume'); // volume | sessions
  const [recMode, setRecMode] = useState('hrv'); // hrv | rhr
  const [healthLog, setHealthLog] = useState([]);

  useEffect(() => {
    getAllHealth().then(setHealthLog).catch(() => {});
  }, []);

  const chartable = series.filter((s) => s.points.length >= 2).slice(0, 8);
  const sel = chartable[Math.min(exIdx, chartable.length - 1)];

  const shortDay = (iso) =>
    new Date(iso + 'T12:00:00').toLocaleDateString(undefined, { day: 'numeric', month: 'numeric' });
  const recent30 = healthLog.slice(-30);
  const hrvPoints = recent30
    .filter((h) => h.hrv)
    .map((h) => ({ label: shortDay(h.date), value: h.hrv }));
  const rhrPoints = recent30
    .filter((h) => h.rhr)
    .map((h) => ({ label: shortDay(h.date), value: h.rhr }));

  // only offer recovery modes that have enough data to chart
  const recModes = [
    hrvPoints.length >= 2 && ['hrv', 'HRV'],
    rhrPoints.length >= 2 && ['rhr', 'Resting HR'],
  ].filter(Boolean);
  const activeRec = recModes.some(([v]) => v === recMode)
    ? recMode
    : recModes[0]?.[0];

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="brand-sm">PROGRESS</div>
        <div />
      </header>

      {history.length < 2 && recModes.length === 0 ? (
        <div className="center-fill">
          <p className="body" style={{ color: 'var(--muted)', textAlign: 'center' }}>
            Charts unlock after a couple of logged sessions.
            <br />
            Keep training — the picture builds itself.
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
              <div className="stat-tile__label">Week streak (≥3)</div>
              <div className="stat-tile__value">{streak} <span className="stat-tile__unit">wks</span></div>
            </div>
          </div>

          {chartable.length > 0 && sel && (
            <div className="card">
              <div className="card__label">Best set weight per session (kg)</div>
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
              <LineChart
                points={sel.points.map((p) => ({ label: shortDate(p.date), value: p.w }))}
                unit="kg"
              />
              <div className="mono chart-table">
                {sel.points.slice(-4).reverse().map((p) => (
                  <div key={p.date} className="row-between">
                    <span>{fmtDate(p.date)}</span>
                    <span>{p.w}kg</span>
                  </div>
                ))}
              </div>
            </div>
          )}

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
            <p className="mono chart-table" style={{ display: 'block' }}>
              {weekMode === 'volume'
                ? 'Total kg lifted per week, last 8 weeks.'
                : 'Sessions logged per week, last 8 weeks.'}
            </p>
          </div>
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
              {activeRec === 'hrv' ? (
                <LineChart points={hrvPoints} unit="ms" color="var(--chart-teal)" />
              ) : (
                <LineChart points={rhrPoints} color="var(--chart-amber)" />
              )}
              <p className="mono chart-table" style={{ display: 'block' }}>
                {activeRec === 'hrv'
                  ? 'HRV (ms), daily from Watch. Higher and stable is good — dips flag poor recovery.'
                  : 'Resting heart rate (bpm). Lower and stable is good — a climb suggests fatigue or illness.'}
              </p>
            </div>
          )}

          {recModes.length === 0 && (
            <div className="foot-note">
              Recovery charts (HRV, resting HR) appear after two days of Watch
              data — run the Gym Check-in shortcut daily.
            </div>
          )}

          <div style={{ height: 24 }} />
        </>
      )}
    </div>
  );
}
