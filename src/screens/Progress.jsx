import React, { useState, useMemo, useEffect } from 'react';
import { LineChart, BarChart, TrainingHeatmap } from '../components/Charts';
import { TabHeader, StatusPill, SectionHead, ProgressLine, Segmented, PageHero, KpiCard, IconWell, useDesktop } from '../components/Shell';
import Icon from '../components/Icon';
import { exerciseSeries, weeklyBuckets, weekStats, sessionVolume, muscleBalance, goalProgress, biggestMuscleGap, MUSCLE_FIX_TIPS } from '../utils/stats';
import { getAllHealth } from '../db/db';
import { getAISettings } from '../utils/storage';
import { daysAgoStr } from '../utils/helpers';
import { latestBodyWeightKg } from '../utils/calories';
import { weeklyTarget, rangeSummary, compliance, deltaPercent, readiness, toneColor, muscleWeeks } from '../utils/dashboard';

const shortDate = (iso) =>
  new Date(iso + 'T12:00:00').toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'numeric',
  });

const RANGES = { '8w': 56, '3m': 91, '1y': 364 };
const RANGE_NAMES = { '8w': '8 weeks', '3m': '3 months', '1y': '12 months' };
const tonnes = (kg) => (kg >= 10000 ? Math.round(kg / 1000) : (kg / 1000).toFixed(1));

/** A range switch (8 weeks · 3 months · year) over the summary,
 *  consistency heatmap, lift progression, weekly training, muscle
 *  balance, goals and recovery. Phones get one column (the iOS
 *  ProgressView mirrors it); desktops get stat cards and a chart grid. */
export default function Progress({ history }) {
  const desktop = useDesktop();
  const [range, setRange] = useState('8w');
  const [exIdx, setExIdx] = useState(0);
  const [exMetric, setExMetric] = useState('w'); // w = best set weight | e = est. 1RM
  const [weekMode, setWeekMode] = useState('volume'); // volume | sessions
  const [recMode, setRecMode] = useState('hrv'); // hrv | rhr | sleep | weight
  const [healthLog, setHealthLog] = useState([]);
  useEffect(() => {
    getAllHealth().then(setHealthLog).catch(() => {});
  }, []);

  const days = RANGES[range];
  const weeks = days / 7;
  const start = daysAgoStr(days - 1);
  const inRange = useMemo(() => history.filter((s) => s.date >= start), [history, start]);
  const target = weeklyTarget(getAISettings());
  const { streak } = weekStats(history, target);
  const sum = rangeSummary(history, days, latestBodyWeightKg(healthLog));
  const delta = deltaPercent(sum.sessions, sum.prevSessions);
  const pct = compliance(history, weeks, target);

  const heatDays = useMemo(() => {
    const m = new Map();
    for (const s of history) {
      const cur = m.get(s.date) || { volume: 0, count: 0 };
      m.set(s.date, { volume: cur.volume + sessionVolume(s), count: cur.count + 1 });
    }
    return m;
  }, [history]);
  const balance = useMemo(() => muscleBalance(history), [history]);
  const goals = useMemo(() => goalProgress(history, getAISettings().goals), [history]);

  const chartable = exerciseSeries(inRange).filter((s) => s.points.length >= 2).slice(0, 10);
  const sel = chartable[Math.min(exIdx, chartable.length - 1)];

  const health = healthLog.filter((h) => h.date >= start).sort((a, b) => (a.date < b.date ? -1 : 1));
  const recPoints = (field) => health.filter((h) => h[field]).map((h) => ({ label: shortDate(h.date), value: h[field] }));
  const REC = {
    hrv: { label: 'HRV', points: recPoints('hrv'), unit: 'ms', color: 'var(--green)', desc: 'Higher and steady is good.' },
    rhr: { label: 'Resting HR', points: recPoints('rhr'), unit: 'bpm', color: 'var(--amber)', desc: 'Lower and steady is good.' },
    sleep: { label: 'Sleep', points: recPoints('sleepH'), unit: 'h', color: 'var(--green)', desc: 'Under ~6h, the coach eases off.' },
    weight: { label: 'Body wt', points: recPoints('weightKg'), unit: 'kg', color: 'var(--amber)', desc: 'Watch the trend, not the day.' },
  };
  const recModes = Object.entries(REC).filter(([, m]) => m.points.length >= 2).map(([v, m]) => [v, m.label]);
  const activeRec = recModes.some(([v]) => v === recMode) ? recMode : recModes[0]?.[0];
  const ready = readiness(history, healthLog);
  const empty = history.length < 2 && recModes.length === 0;

  // ── cards shared by both layouts ──

  const rangeSwitch = (
    <Segmented options={[['8w', '8 Weeks'], ['3m', '3 Months'], ['1y', 'Year']]} value={range} onChange={setRange} />
  );

  const consistency = (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'flex-start' }}>
        <div>
          <div className="hero-title" style={{ fontSize: 22 }}>Consistency</div>
          <div style={{ fontSize: 12.5, color: 'var(--muted)' }}>{desktop ? 'Every training day, last 12 months' : 'Daily training frequency'}</div>
        </div>
        <StatusPill text={`${pct}% compliance`} color={pct >= 80 ? 'var(--green)' : 'var(--amber-text)'} />
      </div>
      <div style={{ margin: '12px 0 8px' }}>
        <TrainingHeatmap days={heatDays} weeks={desktop ? 52 : weeks} />
      </div>
      <div className="row-between" style={{ alignItems: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        <span>Target: {target} sessions/wk</span>
        <span className="heat-legend">
          <span className="caps">Less</span>
          {[0.4, 0.7, 1].map((o) => <i key={o} style={{ background: `rgba(245,158,11,${o})` }} />)}
          <span className="caps">More</span>
        </span>
      </div>
    </div>
  );

  const lift = sel && (() => {
    const e1 = sel.points.filter((p) => p.e != null);
    const showE1 = e1.length >= 2;
    const metric = exMetric === 'e' && showE1 ? 'e' : 'w';
    const pts = metric === 'e' ? e1 : sel.points;
    const vals = pts.map((p) => (metric === 'e' ? p.e : p.w));
    const latest = vals[vals.length - 1];
    const first = vals[0];
    const isPR = latest >= Math.max(...vals) && latest > first;
    const d = Math.round((latest - first) * 10) / 10;
    return (
      <div className="card">
        <div className="row-between" style={{ alignItems: 'flex-start' }}>
          <div style={{ minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              {isPR && <StatusPill text="New PR" color="var(--amber-text)" dot={false} />}
              <span className="caps">Lift progression</span>
            </div>
            <div className="hero-title" style={{ fontSize: 22, marginTop: 4 }}>{sel.name}</div>
          </div>
          {showE1 && (
            <div style={{ display: 'flex', gap: 4 }}>
              {[['w', 'Weight'], ['e', '1RM']].map(([v, l]) => (
                <button key={v} className={'chip' + (metric === v ? ' chip-on' : '')} onClick={() => setExMetric(v)}>{l}</button>
              ))}
            </div>
          )}
        </div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, margin: '6px 0' }}>
          <span className="hero-title" style={{ fontSize: 36, color: 'var(--amber-text)' }}>{latest}</span>
          <span className="caps" style={{ color: 'var(--amber-text)', fontSize: 15 }}>kg</span>
          <span className="caps" style={{ fontSize: 12, color: d >= 0 ? 'var(--green)' : 'var(--red)' }}>
            {d >= 0 ? '+' : ''}{d} kg progression
          </span>
        </div>
        <LineChart
          points={pts.map((p) => ({ label: shortDate(p.date), value: metric === 'e' ? p.e : p.w }))}
          unit="kg"
          {...(desktop ? { width: 760, height: 230 } : {})}
        />
        <div className={desktop ? 'chip-row chip-row--wrap' : 'chip-row'} style={{ marginTop: 8 }}>
          {chartable.map((s, i) => (
            <button key={s.name} className={'chip' + (s === sel ? ' chip-on' : '')} onClick={() => setExIdx(i)}>{s.name}</button>
          ))}
        </div>
      </div>
    );
  })();

  const weekly = (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'center', marginBottom: 10 }}>
        <span className="caps">Weekly training</span>
        <div style={{ display: 'flex', gap: 6 }}>
          {[['volume', 'Volume'], ['sessions', 'Sessions']].map(([v, l]) => (
            <button key={v} className={'chip' + (weekMode === v ? ' chip-on' : '')} onClick={() => setWeekMode(v)}>{l}</button>
          ))}
        </div>
      </div>
      {(() => {
        const buckets = weeklyBuckets(history, Math.min(weeks, 12));
        return weekMode === 'volume' ? (
          <BarChart bars={buckets.map((w) => ({ label: shortDate(w.start), value: w.volume }))} unit="kg" {...(desktop ? { height: 255 } : {})} />
        ) : (
          <BarChart bars={buckets.map((w) => ({ label: shortDate(w.start), value: w.count }))} color="var(--chart-green)" {...(desktop ? { height: 255 } : {})} />
        );
      })()}
    </div>
  );

  const goalsCard = goals.length > 0 && (
    <div className="card">
      <div className="card__label">Goals</div>
      {goals.map((g, i) => (
        <div key={i} style={{ marginTop: i ? 12 : 0 }}>
          <div className="row-between">
            <span className="body" style={{ fontSize: 14 }}>{g.text}</span>
            {g.target != null && (
              <span className="caps" style={{ fontSize: 15, color: 'var(--amber-text)' }}>{g.current} / {g.target}{g.unit}</span>
            )}
          </div>
          {g.target != null && (
            <div style={{ marginTop: 6 }}>
              <ProgressLine fraction={g.current / g.target} color={g.current >= g.target ? 'var(--green)' : 'var(--amber)'} height={7} />
            </div>
          )}
        </div>
      ))}
    </div>
  );

  const recovery = recModes.length > 0 ? (() => {
    const m = REC[activeRec];
    const latest = m.points[m.points.length - 1].value;
    const prior = m.points.slice(-8, -1).map((p) => p.value);
    const avg = prior.length ? prior.reduce((a, b) => a + b, 0) / prior.length : null;
    const r1 = (v) => Math.round(v * 10) / 10;
    return (
      <div className="card">
        <div className="row-between" style={{ alignItems: 'center' }}>
          <span className="caps"><Icon name="ecg_heart" size={18} style={{ color: 'var(--green)' }} /> Recovery &amp; {m.label}</span>
          {ready && <StatusPill text={ready.tone === 'good' ? 'Optimal recovery' : ready.tone === 'ok' ? 'Steady' : 'Strained'} color={toneColor(ready.tone)} />}
        </div>
        <div className="row-between" style={{ alignItems: 'baseline', margin: '6px 0' }}>
          <span><span className="hero-title" style={{ fontSize: 38 }}>{r1(latest)}</span> <span className="caps">{m.unit}</span></span>
          {avg != null && (
            <span className="caps" style={{ fontSize: 11, color: 'var(--green)' }}>
              {latest - avg >= 0 ? '+' : ''}{r1(latest - avg)}{m.unit} vs 7d avg
            </span>
          )}
        </div>
        <LineChart points={m.points} unit={m.unit} color={m.color} {...(desktop ? { height: 290 } : {})} />
        <div className="chip-row" style={{ marginTop: 8 }}>
          {recModes.map(([v, l]) => (
            <button key={v} className={'chip' + (activeRec === v ? ' chip-on' : '')} onClick={() => setRecMode(v)}>{l}</button>
          ))}
        </div>
        <p className="card__detail">{m.desc}</p>
      </div>
    );
  })() : (
    <div className="foot-note">Recovery charts appear after two days of Health data.</div>
  );

  // ── phone ──

  if (!desktop) {
    return (
      <div className="screen screen--slide-in">
        <TabHeader title="Progress" />
        {rangeSwitch}
        {empty ? (
          <p className="body" style={{ color: 'var(--muted)', textAlign: 'center', padding: '60px 0' }}>
            Log two sessions to unlock charts.
          </p>
        ) : (
          <>
            <div className="card summary-card">
              <div>
                <span className="caps">Sessions</span>
                <b>{sum.sessions}</b>
                <span className="caps" style={{ color: delta == null ? 'var(--muted)' : delta >= 0 ? 'var(--green)' : 'var(--red)' }}>
                  {delta == null ? 'Logged' : `${delta >= 0 ? '↗ +' : '↘ '}${delta}%`}
                </span>
              </div>
              <div>
                <span className="caps">Volume</span>
                <b>{tonnes(sum.volume)}T</b>
                <span className="caps">Lifted</span>
              </div>
              <div>
                <span className="caps">Streak</span>
                <b>{streak}wk</b>
                <span className="caps" style={{ color: streak ? 'var(--amber-text)' : 'var(--muted)' }}>{streak ? 'Active' : '—'}</span>
              </div>
            </div>
            {consistency}
            {lift}
            {weekly}
            {balance.length > 0 && (
              <div className="card">
                <SectionHead title="Muscle balance" trailing="14 days" trailingColor="var(--muted)" />
                <BalanceBars balance={balance} />
              </div>
            )}
            {goalsCard}
            {recovery}
          </>
        )}
      </div>
    );
  }

  // ── desktop ──

  return (
    <div className="screen screen--fade-in">
      <TabHeader title="Progress" />
      <PageHero
        kicker={`Last ${RANGE_NAMES[range]}`}
        title="Progress & analytics"
        sub={empty ? 'Log two sessions to unlock charts.' : `${sum.sessions} sessions · ${tonnes(sum.volume)}t lifted · ${pct}% of your weekly target`}
      >
        {rangeSwitch}
      </PageHero>

      {!empty && (
        <>
          <div className="kpi-grid">
            <KpiCard
              label="Sessions"
              icon="fitness_center"
              value={sum.sessions}
              note={delta == null ? 'Logged' : `${delta >= 0 ? '+' : ''}${delta}% vs prior`}
              noteColor={delta == null ? 'var(--muted)' : delta >= 0 ? 'var(--green)' : 'var(--red)'}
            />
            <KpiCard label="Volume lifted" icon="scale" value={tonnes(sum.volume)} unit="T" note={RANGE_NAMES[range]} />
            <KpiCard label="Consistency streak" icon="local_fire_department" value={streak} unit="WK" note={streak ? 'Active' : 'Start one'} noteColor={streak ? 'var(--amber-text)' : 'var(--muted)'}>
              <div style={{ display: 'flex', gap: 5 }}>
                {Array.from({ length: 8 }, (_, i) => (
                  <span key={i} style={{ flex: 1, height: 6, borderRadius: 3, background: i < Math.min(streak, 8) ? 'var(--amber)' : 'var(--bg-high)' }} />
                ))}
              </div>
            </KpiCard>
            <KpiCard label="Compliance" icon="track_changes" value={pct} unit="%" note={`Target ${target}/wk`}>
              <ProgressLine fraction={pct / 100} color={pct >= 80 ? 'var(--green)' : 'var(--amber)'} height={5} />
            </KpiCard>
          </div>

          <div className="desk-grid desk-grid--2-1">
            <MuscleWeekCard history={history} weeks={Math.min(weeks, 12)} />
            {weekly}
          </div>

          <div className="desk-grid desk-grid--2-1">
            {lift || <div className="card"><span className="caps">Lift progression</span><p className="body" style={{ color: 'var(--muted)', marginTop: 8 }}>Log an exercise twice in this range to chart it.</p></div>}
            {recovery}
          </div>

          {balance.length > 0 && <BalanceSection balance={balance} history={history} />}

          <div className={goalsCard ? 'desk-grid desk-grid--2-1' : undefined}>
            {consistency}
            {goalsCard}
          </div>
        </>
      )}
    </div>
  );
}

function BalanceBars({ balance }) {
  const max = Math.max(...balance.map((b) => b.sets), 1);
  return balance.map((b) => {
    const gap = b.lastDaysAgo != null && b.lastDaysAgo >= 10;
    return (
      <div key={b.group} className="balance-row">
        <span className="balance-row__name">{b.group}</span>
        <div style={{ flex: 1 }}>
          <ProgressLine fraction={Math.max(b.sets / max, b.sets ? 0.06 : 0)} color={gap ? 'var(--red)' : 'var(--amber)'} height={7} />
        </div>
        <span className={'balance-row__meta' + (gap ? ' balance-row__meta--gap' : '')}>
          {b.sets ? `${b.sets} sets` : `${b.lastDaysAgo}d ago`}
        </span>
      </div>
    );
  });
}

/** Desktop: sets per muscle group per week, as an amber intensity grid. */
function MuscleWeekCard({ history, weeks }) {
  const { weeks: cols, rows, max } = useMemo(() => muscleWeeks(history, weeks), [history, weeks]);
  return (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'flex-start' }}>
        <div>
          <span className="caps">Training load</span>
          <div className="hero-title" style={{ fontSize: 22, marginTop: 2 }}>Sets per muscle group</div>
        </div>
        <span className="heat-legend">
          <span className="caps">Fewer</span>
          {[0.25, 0.55, 1].map((o) => <i key={o} style={{ background: `rgba(245,158,11,${o})` }} />)}
          <span className="caps">More</span>
        </span>
      </div>
      <div className="muscle-heat" style={{ gridTemplateColumns: `90px repeat(${cols.length}, minmax(0, 1fr))` }}>
        <span />
        {cols.map((w) => <span key={w} className="caps muscle-heat__week">{shortDate(w)}</span>)}
        {rows.map((r) => (
          <React.Fragment key={r.group}>
            <span className="muscle-heat__name">{r.group}</span>
            {r.sets.map((n, i) => (
              <span
                key={i}
                className="muscle-heat__cell"
                title={`${r.group}, week of ${shortDate(cols[i])}: ${n} set${n === 1 ? '' : 's'}`}
                style={{ background: n ? `rgba(245,158,11,${0.2 + 0.8 * (n / max)})` : 'var(--bg-high)' }}
              >
                {n || ''}
              </span>
            ))}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

/** Desktop: one tile per muscle group (last 14 days) + the biggest gap, if any. */
function BalanceSection({ balance, history }) {
  const gap = biggestMuscleGap(history);
  const max = Math.max(...balance.map((b) => b.sets), 1);
  return (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'flex-start', gap: 16 }}>
        <div>
          <span className="caps">Muscle balance · 14 days</span>
          <div className="hero-title" style={{ fontSize: 22, marginTop: 2 }}>Where your sets went</div>
        </div>
        {gap && (
          <div className="gap-alert">
            <IconWell icon="warning" tint="var(--red)" size={30} />
            <span>
              <b>{gap.group}</b> not trained for {gap.lastDaysAgo} days
              {MUSCLE_FIX_TIPS[gap.group] && <span className="gap-alert__tip"> · try {MUSCLE_FIX_TIPS[gap.group]}</span>}
            </span>
          </div>
        )}
      </div>
      <div className="balance-tiles">
        {balance.map((b) => {
          const late = b.lastDaysAgo != null && b.lastDaysAgo >= 10;
          return (
            <div key={b.group} className="balance-tile">
              <div className="row-between">
                <span style={{ fontWeight: 600 }}>{b.group}</span>
                <span className="caps" style={{ color: late ? 'var(--red)' : 'var(--amber-text)', fontSize: 15 }}>{b.sets} sets</span>
              </div>
              <div style={{ margin: '8px 0 6px' }}>
                <ProgressLine fraction={Math.max(b.sets / max, b.sets ? 0.06 : 0)} color={late ? 'var(--red)' : 'var(--amber)'} height={6} />
              </div>
              <div className="row-between" style={{ fontSize: 12.5, color: 'var(--muted)' }}>
                <span>{b.volume ? `${b.volume.toLocaleString()} kg` : 'No weighted sets'}</span>
                <span style={late ? { color: 'var(--red)' } : undefined}>
                  {b.lastDaysAgo === 0 ? 'Today' : b.lastDaysAgo != null ? `${b.lastDaysAgo}d ago` : '—'}
                </span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
