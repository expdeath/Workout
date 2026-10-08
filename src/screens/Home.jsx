import React, { useEffect, useState } from 'react';
import { fmtDate, fmtSet, setLogged, todayStr } from '../utils/helpers';
import { weekStats, sessionVolume, exerciseSeries, prRecords, logMode } from '../utils/stats';
import { getAISettings } from '../utils/storage';
import { getAllHealth } from '../db/db';
import { calorieStats, latestBodyWeightKg } from '../utils/calories';
import {
  readiness as readinessOf,
  toneColor,
  weeklyTarget,
  rangeSummary,
  compliance,
  deltaPercent,
  projectedLoad,
  averageRPE,
  kgShort,
  milestones,
} from '../utils/dashboard';
import QuickCardioSheet from '../components/QuickCardioSheet';
import Icon from '../components/Icon';
import { LineChart, TrainingHeatmap } from '../components/Charts';
import { TabHeader, StatusPill, SectionHead, ProgressLine, StatBlock, LaunchTile, IconWell, useShell } from '../components/Shell';

const WEEK_MS = 7 * 86400000;
const LAUNCH = [
  ['run', 'run', 'Run'],
  ['cycle', 'ride', 'Ride'],
  ['walk', 'walk', 'Walk'],
  ['hike', 'hike', 'Hike'],
];

/** The Today tab. Phones get one column (readiness, this week, start,
 *  quick launch, today's plan, notes); desktops get the 3-column cockpit
 *  with recent workouts, consistency, lift progression and records. */
export default function Home({ todayPlan, history, syncInfo, weeklyReview, monthlyReport, onStart, onQuickStart, onResume, onQuickCardio, onOpenSession, onAddPast }) {
  const { displayName, go } = useShell();
  const [quickCardio, setQuickCardio] = useState(null); // null | 'run' | 'cycle' | 'walk' | 'hike'
  const [health, setHealth] = useState([]);
  const [dismissed, setDismissed] = useState(() => {
    try {
      return localStorage.getItem('coach:noticeDismissed') === todayStr();
    } catch {
      return false;
    }
  });
  useEffect(() => {
    getAllHealth().then(setHealth).catch(() => {});
  }, [history]);

  const name = displayName.split(' ')[0];
  const doneToday = todayPlan && todayPlan.finished;
  const inProgress = todayPlan && !todayPlan.finished;
  const settings = getAISettings();
  const target = weeklyTarget(settings);
  const { thisWeek, streak } = weekStats(history, target);
  const kcal = calorieStats(history, latestBodyWeightKg(health)).thisWeek;
  const ready = readinessOf(history, health);
  const showReview = weeklyReview?.text && Date.now() - (weeklyReview.at || 0) < WEEK_MS;
  const showMonthly = monthlyReport?.text && Date.now() - (monthlyReport.at || 0) < 10 * 86400000;

  const title = doneToday
    ? name ? `Nice work, ${name}.` : 'Session done.'
    : inProgress
    ? `${todayPlan.plan.sessionType} in progress`
    : name ? `Ready, ${name}?` : 'Ready?';
  const startLabel = inProgress ? `Resume ${todayPlan.plan.sessionType}` : doneToday ? 'Plan another session' : 'Start workout';
  const start = inProgress ? onResume : onStart;
  const pill = doneToday ? <StatusPill text="Done" /> : ready ? <StatusPill text={ready.label} color={toneColor(ready.tone)} /> : null;
  const dateCaps = new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' });

  const dismiss = () => {
    setDismissed(true);
    try {
      localStorage.setItem('coach:noticeDismissed', todayStr());
    } catch { /* private mode */ }
  };

  // ── shared cards ──

  const launch = (
    <>
      <SectionHead title="Quick launch" trailing="Manual activity" onTrailing={onAddPast} />
      <div className="launch-row">
        {!inProgress && <LaunchTile icon="timer" label="Quick" onClick={onQuickStart} />}
        {LAUNCH.map(([kind, icon, label]) => (
          <LaunchTile key={kind} icon={icon} label={label} tint="var(--green)" onClick={() => setQuickCardio(kind)} />
        ))}
      </div>
    </>
  );

  const focus = (
    <>
      <SectionHead
        title="Today's focus"
        trailing={!todayPlan ? 'Not planned' : todayPlan.finished ? 'Completed' : 'Scheduled'}
        trailingColor={todayPlan?.finished ? 'var(--green)' : todayPlan ? 'var(--amber-text)' : 'var(--muted)'}
      />
      {todayPlan ? <PlanCard t={todayPlan} history={history} onOpen={onResume} /> : (
        <div className="card" style={{ marginTop: 0 }}>
          <div className="hero-title" style={{ fontSize: 26 }}>No plan yet</div>
          <p className="body" style={{ color: 'var(--muted)', marginTop: 4 }}>
            A one-minute check-in and the coach builds today's session around your recovery.
          </p>
        </div>
      )}
    </>
  );

  const notice = ready && !dismissed && (
    <div className="notice">
      <IconWell icon={ready.tone === 'low' ? 'warning' : 'health_and_safety'} tint={toneColor(ready.tone)} size={32} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="caps" style={{ fontSize: 12, color: toneColor(ready.tone) }}>
          {ready.tone === 'low' ? 'Go easier today' : ready.tone === 'good' ? 'Recovery looks good' : 'Normal recovery'}
        </div>
        <p className="body" style={{ marginTop: 2 }}>{ready.note}</p>
      </div>
      <button className="icon-btn" style={{ width: 28, height: 28 }} aria-label="Dismiss" onClick={dismiss}>
        <Icon name="x" size={18} />
      </button>
    </div>
  );

  const reviews = (
    <>
      {showMonthly && (
        <div className="card">
          <SectionHead title="Monthly report" trailing={`${monthlyReport.sum?.count} sessions`} />
          <Clamped text={monthlyReport.text} />
        </div>
      )}
      {showReview && (
        <div className="card">
          <SectionHead title="Weekly review" trailing={`${weeklyReview.count} sessions`} />
          <Clamped text={weeklyReview.text} />
        </div>
      )}
      {syncInfo?.state === 'error' && (
        <div className="foot-note" style={{ color: 'var(--red)' }}>Sync error — {syncInfo.message}</div>
      )}
    </>
  );

  return (
    <div className="screen screen--fade-in">
      <TabHeader title="Today" />

      {/* ── phone ── */}
      <div className="dash-mobile">
        <div className="caps">{dateCaps}</div>
        <div className="row-between" style={{ alignItems: 'center', marginTop: 4 }}>
          <h1 className="hero-title">{title}</h1>
          {pill}
        </div>
        <div className="stat-row" style={{ marginTop: 16 }}>
          <StatBlock value={thisWeek} label="This week" />
          <StatBlock value={streak} label="Streak (wks)" color="var(--amber-text)" />
          <StatBlock value={kcal >= 10000 ? `${Math.floor(kcal / 1000)}k` : kcal} label="Active kcal" />
        </div>
        <button className="big-btn" onClick={start}>
          <Icon name="play_arrow" size={24} fill /> {startLabel}
        </button>
        {launch}
        {focus}
        {notice}
        {reviews}
      </div>

      {/* ── desktop ── */}
      <div className="dash-desktop">
        <div className="dash-hero">
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              {pill}
              <span style={{ color: 'var(--muted)', fontSize: 14 }}>{dateCaps}</span>
            </div>
            <h1 className="hero-title" style={{ marginTop: 6 }}>{title}</h1>
          </div>
          <div className="dash-hero__actions">
            <button className="small-btn" style={{ padding: '12px 20px' }} onClick={onAddPast}>
              <Icon name="add" size={18} /> Quick log
            </button>
            <button className="big-btn" onClick={start}>
              <Icon name="play_arrow" size={22} fill /> {startLabel}
            </button>
          </div>
        </div>
        <Kpis history={history} health={health} target={target} streak={streak} thisWeek={thisWeek} />
        <div className="dash-grid" style={{ marginTop: 8 }}>
          <div>
            {launch}
            {focus}
            {notice}
            <Devices health={health} />
          </div>
          <div>
            <Recent history={history} target={target} thisWeek={thisWeek} onOpen={onOpenSession} onLog={onAddPast} />
            {reviews}
          </div>
          <div>
            <Consistency history={history} target={target} />
            <Lift history={history} />
            <Recovery health={health} ready={ready} />
            <RecordsCard history={history} onAll={() => go('records')} />
          </div>
        </div>
      </div>

      {quickCardio && (
        <QuickCardioSheet kind={quickCardio} onClose={() => setQuickCardio(null)} onSave={onQuickCardio} />
      )}
    </div>
  );
}

function PlanCard({ t, history, onOpen }) {
  const p = t.plan;
  const total = t.log.reduce((a, r) => a + r.length, 0);
  const done = t.log.reduce((a, r) => a + r.filter((s) => s.done).length, 0);
  const load = projectedLoad(p, history);
  const rpe = averageRPE(p);
  const meta = [p.estTimeMin ? `${p.estTimeMin} min` : null, rpe ? `RPE ${rpe}` : null, `${p.exercises.length} exercises`]
    .filter(Boolean)
    .join(' • ');
  return (
    <div className="card" style={{ marginTop: 0 }}>
      <div className="row-between" style={{ alignItems: 'flex-start' }}>
        <div style={{ minWidth: 0 }}>
          <div className="hero-title" style={{ fontSize: 26 }}>{p.title || p.sessionType}</div>
          <div className="caps" style={{ color: 'var(--amber-text)', marginTop: 4 }}>{meta}</div>
        </div>
        <IconWell icon="open_in_full" />
      </div>
      <div style={{ margin: '14px 0' }}>
        <ProgressLine fraction={total ? done / total : 0} color={t.finished ? 'var(--green)' : 'var(--amber)'} />
      </div>
      <div className="row-between" style={{ alignItems: 'center' }}>
        <span style={{ fontSize: 13, color: 'var(--muted)' }}>
          {load > 0 ? `Target load: ${kgShort(load)} kg volume` : `${done}/${total} sets done`}
        </span>
        <button className="small-btn" disabled={t.finished} onClick={onOpen}>
          {t.finished ? 'Done' : done ? 'Resume' : 'Start'} <Icon name="arrow_forward" size={16} />
        </button>
      </div>
    </div>
  );
}

// Long coach text clamped to four lines; tap to read the rest.
function Clamped({ text }) {
  const [open, setOpen] = useState(false);
  return (
    <p className={`body clamp${open ? ' clamp--open' : ''}`} onClick={() => setOpen(!open)}>
      {text}
    </p>
  );
}

// ── desktop cockpit cards ──

function Kpis({ history, health, target, streak, thisWeek }) {
  const cycle = rangeSummary(history, 28, latestBodyWeightKg(health));
  const delta = deltaPercent(cycle.volume, rangeSummary(history, 56, latestBodyWeightKg(health)).volume - cycle.volume);
  return (
    <div className="dash-kpis">
      <div className="card" style={{ marginTop: 0 }}>
        <div className="row-between"><span className="caps">Total sessions</span><Icon name="fitness_center" size={18} style={{ color: 'var(--amber-text)' }} /></div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 10 }}>
          <span className="hero-title" style={{ fontSize: 42 }}>{history.length}</span>
          <span className="caps" style={{ color: 'var(--green)' }}>+{thisWeek} this week</span>
        </div>
        <div style={{ marginTop: 8 }}><ProgressLine fraction={thisWeek / target} height={4} /></div>
      </div>
      <div className="card" style={{ marginTop: 0 }}>
        <div className="row-between"><span className="caps">Consistency streak</span><Icon name="local_fire_department" fill size={18} style={{ color: 'var(--amber-text)' }} /></div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 10 }}>
          <span className="hero-title" style={{ fontSize: 42 }}>{streak}</span>
          <span className="caps">Weeks unbroken</span>
        </div>
        <div style={{ display: 'flex', gap: 5, marginTop: 8 }}>
          {Array.from({ length: 8 }, (_, i) => (
            <span key={i} style={{ flex: 1, height: 6, borderRadius: 3, background: i < Math.min(streak, 8) ? 'var(--amber)' : 'var(--bg-high)' }} />
          ))}
        </div>
      </div>
      <div className="card" style={{ marginTop: 0 }}>
        <div className="row-between"><span className="caps">Active volume</span><Icon name="scale" size={18} style={{ color: 'var(--amber-text)' }} /></div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 10 }}>
          <span className="hero-title" style={{ fontSize: 42 }}>
            {(cycle.volume / 1000).toFixed(cycle.volume >= 10000 ? 0 : 1)}<span style={{ color: 'var(--amber)', fontSize: 28 }}>T</span>
          </span>
          <span className="caps">Last 4 weeks</span>
        </div>
        <div className="row-between" style={{ marginTop: 8, fontSize: 13, color: 'var(--muted)' }}>
          <span>vs previous 4 weeks</span>
          {delta != null && <span className="caps" style={{ color: delta >= 0 ? 'var(--green)' : 'var(--red)' }}>{delta >= 0 ? '+' : ''}{delta}%</span>}
        </div>
      </div>
    </div>
  );
}

function Devices({ health }) {
  const last = [...health].sort((a, b) => (a.date < b.date ? 1 : -1))[0];
  return (
    <div className="card">
      <SectionHead title="Devices" trailing={last?.date === todayStr() ? 'Live' : null} trailingColor="var(--green)" />
      <div className="row-between" style={{ alignItems: 'center', padding: 8, background: 'var(--bg-pill)', borderRadius: 'var(--radius-sm)' }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <Icon name="watch" size={20} />
          <span>
            <span style={{ display: 'block', fontWeight: 500, fontSize: 14 }}>Apple Watch</span>
            <span style={{ fontSize: 12, color: 'var(--muted)' }}>{last ? `Last data ${fmtDate(last.date)}` : 'No data yet'}</span>
          </span>
        </span>
        {last?.hrv ? <span className="caps" style={{ color: 'var(--amber-text)' }}>HRV {Math.round(last.hrv)}</span> : null}
      </div>
    </div>
  );
}

function Recent({ history, target, thisWeek, onOpen, onLog }) {
  const recent = [...history].reverse().slice(0, 3);
  const [first, ...rest] = recent;
  const pct = Math.min(100, Math.round((thisWeek / target) * 100));
  return (
    <>
      <div className="row-between" style={{ alignItems: 'center', margin: '18px 0 10px' }}>
        <span className="hero-title" style={{ fontSize: 24 }}>Recent workouts</span>
        <button className="caps section-head__action" style={{ color: 'var(--amber-text)' }} onClick={onLog}>+ Log workout</button>
      </div>
      <div className="card" style={{ marginTop: 0 }}>
        <div className="row-between"><span className="caps">Weekly target</span><span className="caps" style={{ color: 'var(--amber-text)' }}>{pct}% complete</span></div>
        <div style={{ margin: '8px 0' }}><ProgressLine fraction={pct / 100} height={7} /></div>
        <div className="row-between" style={{ fontSize: 12.5, color: 'var(--muted)' }}>
          <span>{thisWeek} of {target} sessions finished</span>
          <span>{thisWeek >= target ? 'Target hit' : `${target - thisWeek} to go`}</span>
        </div>
      </div>
      {first && (
        <div className="card card--tappable" onClick={() => onOpen(first)}>
          <div className="row-between" style={{ alignItems: 'flex-start' }}>
            <div>
              <span className="caps" style={{ color: 'var(--amber-text)' }}>Completed</span>
              <span style={{ fontSize: 12.5, color: 'var(--muted)', marginLeft: 8 }}>{fmtDate(first.date)}</span>
              <div className="hero-title" style={{ fontSize: 26, marginTop: 2 }}>{first.plan.title || first.plan.sessionType}</div>
            </div>
            {first.durationMin ? <span className="caps" style={{ color: 'var(--text)', background: 'var(--bg-high)', padding: '4px 8px', borderRadius: 6 }}>{first.durationMin} min</span> : null}
          </div>
          <div className="caps" style={{ background: 'var(--bg-input)', borderRadius: 'var(--radius-sm)', padding: 8, marginTop: 10, fontSize: 15, color: 'var(--text)' }}>
            {sessionVolume(first).toLocaleString()} kg / {first.log.flat().filter(setLogged).length} sets
            {first.fin ? <span style={{ color: 'var(--amber-text)' }}> / RPE {first.fin.rpe}</span> : null}
          </div>
          {first.plan.exercises.slice(0, 3).map((ex, i) => {
            const best = (first.log[i] || []).filter(setLogged).sort((a, b) => (parseFloat(b.weight) || 0) - (parseFloat(a.weight) || 0))[0];
            return (
              <div key={i} className="sum-row" style={{ background: 'var(--bg-pill)', padding: '8px 10px', borderRadius: 'var(--radius-sm)', marginTop: 6 }}>
                <span>{ex.name}</span>
                <span className="caps" style={{ color: 'var(--amber-text)', fontSize: 15 }}>{best ? fmtSet(best) : '—'}</span>
              </div>
            );
          })}
        </div>
      )}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
        {rest.map((s) => (
          <div key={s.id || s.date} className="card card--tappable" onClick={() => onOpen(s)}>
            <span className="caps" style={{ fontSize: 11 }}>{fmtDate(s.date)}</span>
            <div style={{ fontWeight: 500, marginTop: 6 }}>{s.plan.exercises.every((e) => logMode(e.name, s.plan.sessionType) === 'cardio') ? s.plan.exercises[0]?.name : s.plan.sessionType}</div>
            <div style={{ fontSize: 12.5, color: 'var(--muted)' }}>
              {s.durationMin ? `${s.durationMin} min` : ''}{s.fin ? ` • RPE ${s.fin.rpe}` : ''}
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

function Consistency({ history, target }) {
  const days = new Map();
  for (const s of history) {
    const d = days.get(s.date) || { count: 0, volume: 0 };
    days.set(s.date, { count: d.count + 1, volume: d.volume + sessionVolume(s) });
  }
  const pct = compliance(history, 8, target);
  return (
    <div className="card" style={{ marginTop: 18 }}>
      <div className="row-between" style={{ alignItems: 'center', marginBottom: 10 }}>
        <span className="caps" style={{ color: 'var(--text)' }}><Icon name="calendar_month" size={18} style={{ color: 'var(--amber-text)' }} /> Training consistency</span>
        <StatusPill text={`${pct}% compliance`} color={pct >= 80 ? 'var(--green)' : 'var(--amber-text)'} />
      </div>
      <TrainingHeatmap days={days} weeks={8} cellHeight={14} />
      <div style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 8 }}>8 weeks · target {target}/wk</div>
    </div>
  );
}

function Lift({ history }) {
  const s = exerciseSeries(history).filter((e) => e.points.length >= 2).sort((a, b) => b.points.length - a.points.length)[0];
  if (!s) return null;
  const vals = s.points.map((p) => p.w);
  const latest = vals[vals.length - 1];
  const first = vals[0];
  return (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'flex-start' }}>
        <div>
          <span className="caps">Lift progression</span>
          <div className="hero-title" style={{ fontSize: 22, marginTop: 2 }}>{s.name}</div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div className="hero-title" style={{ fontSize: 32, color: 'var(--amber-text)' }}>{latest} <span style={{ fontSize: 18 }}>KG</span></div>
          <div className="caps" style={{ color: latest >= first ? 'var(--green)' : 'var(--red)', fontSize: 11 }}>{latest >= first ? '+' : ''}{Math.round((latest - first) * 10) / 10} kg</div>
        </div>
      </div>
      <LineChart points={s.points.map((p) => ({ label: fmtDate(p.date), value: p.w }))} unit="kg" />
    </div>
  );
}

function Recovery({ health, ready }) {
  const pts = [...health].sort((a, b) => (a.date < b.date ? -1 : 1)).filter((h) => h.hrv > 0).slice(-30);
  if (pts.length < 2) return null;
  const latest = pts[pts.length - 1].hrv;
  const prior = pts.slice(-8, -1).map((h) => h.hrv);
  const avg = prior.reduce((a, b) => a + b, 0) / (prior.length || 1);
  return (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'center' }}>
        <span className="caps"><Icon name="ecg_heart" size={18} style={{ color: 'var(--green)' }} /> Recovery &amp; HRV</span>
        {ready && <StatusPill text={ready.tone === 'good' ? 'Optimal recovery' : ready.tone === 'ok' ? 'Steady' : 'Strained'} color={toneColor(ready.tone)} />}
      </div>
      <div className="row-between" style={{ alignItems: 'baseline', marginTop: 6 }}>
        <span><span className="hero-title" style={{ fontSize: 38 }}>{Math.round(latest)}</span> <span className="caps">ms</span></span>
        {prior.length > 0 && <span className="caps" style={{ color: 'var(--green)', fontSize: 11 }}>{latest - avg >= 0 ? '+' : ''}{Math.round(latest - avg)}ms vs 7d avg</span>}
      </div>
      <LineChart points={pts.map((h) => ({ label: fmtDate(h.date), value: Math.round(h.hrv) }))} unit="ms" color="var(--green)" />
    </div>
  );
}

function RecordsCard({ history, onAll }) {
  const ms = milestones(history);
  const earned = ms.filter((m) => m.earned);
  const prs = prRecords(history).filter((r) => r.weight).sort((a, b) => (b.weight.w || 0) - (a.weight.w || 0)).slice(0, 3);
  return (
    <div className="card">
      <div className="row-between" style={{ alignItems: 'center' }}>
        <span className="caps" style={{ color: 'var(--text)' }}><Icon name="emoji_events" size={18} style={{ color: 'var(--amber-text)' }} /> {earned.length} milestones unlocked</span>
        <button className="caps section-head__action" style={{ color: 'var(--amber-text)' }} onClick={onAll}>All records →</button>
      </div>
      <div style={{ display: 'flex', gap: 6, overflowX: 'auto', margin: '10px 0' }}>
        {earned.slice(-4).map((m) => (
          <span key={m.id} className="caps" style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, background: 'var(--bg-pill)', color: 'var(--text-body)', whiteSpace: 'nowrap' }}>
            {m.title}
          </span>
        ))}
      </div>
      {prs.map((r) => (
        <div key={r.name} className="sum-row" style={{ background: 'var(--bg-input)', padding: '8px 10px', borderRadius: 'var(--radius-sm)', marginTop: 6 }}>
          <span>{r.name}</span>
          <span className="caps" style={{ color: 'var(--amber-text)', fontSize: 15 }}>{r.weight.w} kg × {r.weight.reps || '?'}</span>
        </div>
      ))}
    </div>
  );
}
