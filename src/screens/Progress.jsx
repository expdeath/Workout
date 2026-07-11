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

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="brand-sm">PROGRESS</div>
        <div />
      </header>

      {history.length < 2 && hrvPoints.length < 2 && rhrPoints.length < 2 ? (
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
            <div className="card__label">Weekly volume — kg lifted, last 8 weeks</div>
            <BarChart
              bars={weeks.map((w) => ({ label: shortDate(w.start), value: w.volume }))}
              unit="kg"
            />
          </div>

          <div className="card">
            <div className="card__label">Sessions per week</div>
            <BarChart
              bars={weeks.map((w) => ({ label: shortDate(w.start), value: w.count }))}
              color="var(--chart-amber)"
            />
          </div>
          </>
          )}

          {hrvPoints.length >= 2 && (
            <div className="card">
              <div className="card__label">Recovery — HRV (ms), daily from Watch</div>
              <LineChart points={hrvPoints} unit="ms" color="var(--chart-teal)" />
              <p className="mono chart-table" style={{ display: 'block' }}>
                Higher and stable is good — dips flag poor recovery. The coach
                reads this same trend before planning.
              </p>
            </div>
          )}

          {rhrPoints.length >= 2 && (
            <div className="card">
              <div className="card__label">Recovery — resting heart rate (bpm)</div>
              <LineChart points={rhrPoints} color="var(--chart-amber)" />
              <p className="mono chart-table" style={{ display: 'block' }}>
                Lower and stable is good — a climb suggests fatigue or illness.
              </p>
            </div>
          )}

          {hrvPoints.length < 2 && rhrPoints.length < 2 && (
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
