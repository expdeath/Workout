import React, { useEffect, useMemo, useState } from 'react';
import { fmtDate, daysAgoStr } from '../utils/helpers';
import { prRecords, exerciseSeries, weekStats, sessionVolume, muscleGroupOf } from '../utils/stats';
import { getAISettings } from '../utils/storage';
import { milestones, keyMilestones, nextBenchmark, weeklyTarget } from '../utils/dashboard';
import { LineChart } from '../components/Charts';
import { TabHeader, StatusPill, SectionHead, ProgressLine, IconWell, PageHero, KpiCard, useDesktop } from '../components/Shell';
import Icon from '../components/Icon';

/** The honor roll (milestones unlocked), lifetime stats, the milestone
 *  grid with progress, personal records (tap one for its est. 1RM
 *  trend) and the next benchmark in reach. The iOS RecordsView mirrors
 *  the phone layout; desktops get a PR table with a detail panel. */
export default function Records({ history, pick }) {
  if (useDesktop()) return <RecordsDesktop history={history} pick={pick} />;
  return <RecordsPhone history={history} pick={pick} />;
}

// ── Share / export ──

const csvCell = (v) => (/[",\n]/.test(String(v ?? '')) ? `"${String(v).replace(/"/g, '""')}"` : String(v ?? ''));

/** Every personal record as a spreadsheet. */
function exportRecordsCsv(history) {
  const rows = prRecords(history)
    .filter((r) => r.weight)
    .map((r) => [r.name, muscleGroupOf(r.name), r.weight.w, r.weight.reps || '', r.weight.date, r.e1rm?.v ?? '', r.e1rm?.date ?? '', r.count]);
  const csv = [['Exercise', 'Muscle group', 'Best weight (kg)', 'Reps', 'Best set date', 'Est. 1RM (kg)', 'Est. 1RM date', 'Sets logged'], ...rows]
    .map((r) => r.map(csvCell).join(','))
    .join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
  a.download = `coach-records-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/** A short text summary through the system share sheet, or the clipboard. */
async function shareRecords(history) {
  const records = prRecords(history).filter((r) => r.weight).sort((a, b) => (b.e1rm?.v || b.weight.w) - (a.e1rm?.v || a.weight.w));
  const earned = milestones(history).filter((m) => m.earned);
  const text = [
    `My training records — ${history.length} sessions, ${records.length} PRs, ${earned.length} milestones`,
    ...records.slice(0, 6).map((r) => `• ${r.name}: ${r.weight.w} kg × ${r.weight.reps || '?'}${r.e1rm ? ` (est. 1RM ${r.e1rm.v} kg)` : ''}`),
    earned.length ? `Latest milestone: ${earned[earned.length - 1].title}` : '',
  ]
    .filter(Boolean)
    .join('\n');
  if (navigator.share) {
    try {
      await navigator.share({ title: 'My training records', text });
      return 'Shared';
    } catch (e) {
      if (e.name === 'AbortError') return '';
    }
  }
  await navigator.clipboard.writeText(text);
  return 'Copied to clipboard';
}

function ShareExport({ history, compact }) {
  const [msg, setMsg] = useState('');
  const flash = (m) => {
    setMsg(m);
    if (m) setTimeout(() => setMsg(''), 2500);
  };
  const cls = compact ? 'outline-btn' : 'small-btn';
  return (
    <>
      {msg && <span className="caps" style={{ color: 'var(--green)', alignSelf: 'center' }}>{msg}</span>}
      <button className={cls} style={compact ? undefined : { padding: '12px 18px' }} onClick={() => shareRecords(history).then(flash).catch(() => flash("Couldn't share"))}>
        <Icon name="share" size={18} /> Share
      </button>
      <button className={cls} style={compact ? undefined : { padding: '12px 18px' }} onClick={() => { exportRecordsCsv(history); flash('Downloaded'); }}>
        <Icon name="download" size={18} /> Export CSV
      </button>
    </>
  );
}

function RecordsPhone({ history, pick }) {
  const records = prRecords(history)
    .filter((r) => r.weight)
    .sort((a, b) => (a.weight.date < b.weight.date ? 1 : -1));
  const series = exerciseSeries(history);
  const [openEx, setOpenEx] = useState(pick?.name || null); // exercise name or null
  const [showAll, setShowAll] = useState(!!pick);
  useEffect(() => {
    if (!pick) return;
    setOpenEx(pick.name);
    setShowAll(true);
    setTimeout(() => document.querySelector('.pr-card--open')?.scrollIntoView({ block: 'center' }), 50);
  }, [pick]);
  const totalVolume = history.reduce((a, s) => a + sessionVolume(s), 0);
  const { streak } = weekStats(history, weeklyTarget(getAISettings()));
  const all = milestones(history);
  const earned = all.filter((m) => m.earned).length;
  const next = nextBenchmark(history);
  const newCutoff = daysAgoStr(6);

  return (
    <div className="screen screen--slide-in">
      <TabHeader title="Records" />

      <div className="card honor-card">
        <div style={{ minWidth: 0 }}>
          <StatusPill text="Honor roll" color="var(--amber-text)" dot={false} />
          <div className="hero-title" style={{ fontSize: 28, marginTop: 8 }}>
            {earned} milestone{earned === 1 ? '' : 's'} unlocked
          </div>
          <div style={{ fontSize: 13, color: 'var(--green)', marginTop: 4 }}>
            {records.length} personal record{records.length === 1 ? '' : 's'} on the board
          </div>
        </div>
        <span className="honor-card__trophy"><Icon name="emoji_events" size={34} fill /></span>
      </div>

      <div className="stat-row">
        <div className="stat-tile">
          <div className="stat-tile__label">Sessions</div>
          <div className="stat-tile__value">{history.length}</div>
          {history.length > 0 && <div className="caps" style={{ fontSize: 10.5, color: 'var(--green)' }}>Active</div>}
        </div>
        <div className="stat-tile">
          <div className="stat-tile__label">Lifted</div>
          <div className="stat-tile__value">
            {totalVolume >= 10000 ? Math.round(totalVolume / 1000) : (totalVolume / 1000).toFixed(1)}
            <span className="stat-tile__unit">t</span>
          </div>
          <div className="caps" style={{ fontSize: 10.5 }}>Lifetime</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile__label">Streak</div>
          <div className="stat-tile__value">{streak} <span className="stat-tile__unit">wks</span></div>
          {streak >= 2 && <div className="caps" style={{ fontSize: 10.5, color: 'var(--amber-text)' }}>Hot</div>}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
        <ShareExport history={history} compact />
      </div>

      <SectionHead title="Key milestones" trailing={`${earned} of ${all.length} complete`} trailingColor="var(--muted)" />
      <div className="milestone-grid">
        {keyMilestones(history).map((m) => (
          <div key={m.id} className={'milestone' + (m.earned ? ' milestone--earned' : '')}>
            <IconWell icon={m.icon} tint={m.earned ? 'var(--amber-text)' : 'var(--dim)'} size={32} fill={m.earned} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="milestone__title">{m.title}</div>
              {m.earned ? (
                <div style={{ fontSize: 11.5, color: 'var(--green)', display: 'flex', alignItems: 'center', gap: 4 }}>
                  <Icon name="check_circle" size={14} fill /> Unlocked
                </div>
              ) : (
                <>
                  <div style={{ margin: '5px 0 3px' }}><ProgressLine fraction={m.value / m.goal} height={4} /></div>
                  <div style={{ fontSize: 11, color: 'var(--dim)' }}>{m.value} / {m.goal}</div>
                </>
              )}
            </div>
          </div>
        ))}
      </div>

      <SectionHead
        title="Personal records"
        trailing={records.length > 6 ? (showAll ? 'Top 6' : 'All PRs') : null}
        onTrailing={() => setShowAll(!showAll)}
      />
      {records.length === 0 && (
        <p className="body" style={{ color: 'var(--muted)' }}>Log weighted sets to see records.</p>
      )}
      {(showAll ? records : records.slice(0, 6)).map((r) => {
        const isOpen = openEx?.toLowerCase() === r.name.toLowerCase();
        const isNew = r.weight.date >= newCutoff;
        const pts = series.find((e) => e.name === r.name)?.points || [];
        return (
          <div key={r.name} className={'pr-card' + (isOpen ? ' pr-card--open' : '')} onClick={() => setOpenEx(isOpen ? null : r.name)}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <IconWell icon={isNew ? 'star' : 'military_tech'} tint={isNew ? 'var(--amber-text)' : 'var(--muted)'} size={34} fill={isNew} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="pr-card__name">{r.name}</div>
                <div style={{ fontSize: 12.5, color: 'var(--muted)', display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap', overflow: 'hidden' }}>
                  {isNew && <span className="caps" style={{ fontSize: 11, color: 'var(--amber-text)' }}>New</span>}
                  {[muscleGroupOf(r.name), r.e1rm ? `e1RM ${r.e1rm.v}kg` : null].filter(Boolean).join(' · ')}
                </div>
              </div>
              <span style={{ whiteSpace: 'nowrap' }}>
                <span className="hero-title" style={{ fontSize: 22, color: 'var(--amber-text)' }}>{r.weight.w}</span>
                <span className="caps" style={{ fontSize: 11, marginLeft: 3 }}>kg × {r.weight.reps || '?'}</span>
              </span>
              <Icon name="down" size={18} style={{ color: 'var(--dim)', transform: isOpen ? 'rotate(180deg)' : 'none' }} />
            </div>
            {isOpen && pts.length >= 2 && (
              <div style={{ marginTop: 8 }} onClick={(e) => e.stopPropagation()}>
                <LineChart points={pts.map((p) => ({ label: p.date.slice(5), value: p.e || p.w }))} unit="kg" />
              </div>
            )}
            {isOpen && pts.length < 2 && (
              <p style={{ fontSize: 13, color: 'var(--dim)', marginTop: 6 }}>One more session unlocks the trend.</p>
            )}
          </div>
        );
      })}

      {next && (
        <div className="card" style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <IconWell icon="local_fire_department" size={34} fill />
          <div>
            <div style={{ fontWeight: 500 }}>Next benchmark in reach</div>
            <div style={{ fontSize: 13, color: 'var(--muted)' }}>
              {next.goal - next.value} more to unlock {next.title.toLowerCase()}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const tonnes = (kg) => (kg >= 10000 ? Math.round(kg / 1000) : (kg / 1000).toFixed(1));

function RecordsDesktop({ history, pick }) {
  const records = useMemo(
    () => prRecords(history).filter((r) => r.weight).sort((a, b) => (b.e1rm?.v || b.weight.w) - (a.e1rm?.v || a.weight.w)),
    [history]
  );
  const series = useMemo(() => exerciseSeries(history), [history]);
  const [group, setGroup] = useState('All');
  const [picked, setPicked] = useState(pick?.name || null);
  // opened from search: select that lift and bring its row into view
  useEffect(() => {
    if (!pick) return;
    setGroup('All');
    setPicked(pick.name);
    setTimeout(() => document.querySelector('.pr-row--on')?.scrollIntoView({ block: 'center' }), 50);
  }, [pick]);
  const totalVolume = history.reduce((a, s) => a + sessionVolume(s), 0);
  const { streak } = weekStats(history, weeklyTarget(getAISettings()));
  const all = milestones(history);
  const earned = all.filter((m) => m.earned).length;
  const next = nextBenchmark(history);
  const newCutoff = daysAgoStr(6);
  const monthCutoff = daysAgoStr(29);
  const fresh = records.filter((r) => r.weight.date >= monthCutoff).length;

  const groups = ['All', ...new Set(records.map((r) => muscleGroupOf(r.name)))];
  const shown = group === 'All' ? records : records.filter((r) => muscleGroupOf(r.name) === group);
  const sel = shown.find((r) => r.name.toLowerCase() === picked?.toLowerCase()) || shown[0];
  const pts = sel ? series.find((e) => e.name === sel.name)?.points || [] : [];
  const e1 = pts.filter((p) => p.e != null);
  const trend = e1.length >= 2 ? e1.map((p) => ({ label: fmtDate(p.date), value: p.e })) : pts.map((p) => ({ label: fmtDate(p.date), value: p.w }));

  return (
    <div className="screen screen--fade-in">
      <TabHeader title="Records" />
      <PageHero
        kicker="Honor roll"
        title="Records & milestones"
        sub={`${earned} milestone${earned === 1 ? '' : 's'} unlocked · ${records.length} personal record${records.length === 1 ? '' : 's'} on the board`}
      >
        <ShareExport history={history} />
      </PageHero>

      <div className="kpi-grid">
        <KpiCard label="Personal records" icon="emoji_events" value={records.length} note={fresh ? `${fresh} in the last 30 days` : 'All time'} noteColor={fresh ? 'var(--green)' : 'var(--muted)'} />
        <KpiCard label="Lifetime volume" icon="scale" value={tonnes(totalVolume)} unit="T" note="Lifted" />
        <KpiCard label="Sessions" icon="calendar_month" value={history.length} note="Logged" />
        <KpiCard label="Streak" icon="local_fire_department" value={streak} unit="WK" note={streak >= 2 ? 'Hot' : '—'} noteColor="var(--amber-text)" />
      </div>

      <div className="card" style={{ marginTop: 20 }}>
        <div className="row-between" style={{ alignItems: 'baseline' }}>
          <span className="hero-title" style={{ fontSize: 22 }}>Milestones</span>
          <span className="caps" style={{ color: 'var(--muted)' }}>{earned} of {all.length} unlocked</span>
        </div>
        <div className="milestone-wall">
          {all.map((m) => (
            <div key={m.id} className={'milestone-tile' + (m.earned ? ' milestone-tile--earned' : '')}>
              <IconWell icon={m.icon} tint={m.earned ? 'var(--amber-text)' : 'var(--dim)'} size={40} fill={m.earned} />
              <div className="milestone-tile__title">{m.title}</div>
              {m.earned ? (
                <div style={{ fontSize: 12, color: 'var(--green)', display: 'flex', alignItems: 'center', gap: 4 }}>
                  <Icon name="check_circle" size={14} fill /> Unlocked
                </div>
              ) : (
                <>
                  <div style={{ width: '100%', margin: '2px 0' }}><ProgressLine fraction={m.value / m.goal} height={4} /></div>
                  <div style={{ fontSize: 12, color: 'var(--dim)' }}>{m.value} / {m.goal}</div>
                </>
              )}
            </div>
          ))}
        </div>
      </div>

      <div className="desk-grid desk-grid--2-1">
        <div className="card">
          <div className="row-between" style={{ alignItems: 'center', marginBottom: 6 }}>
            <span className="hero-title" style={{ fontSize: 22 }}>Personal records</span>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
              {groups.map((g) => (
                <button key={g} className={'chip' + (group === g ? ' chip-on' : '')} onClick={() => setGroup(g)}>{g}</button>
              ))}
            </div>
          </div>
          {shown.length === 0 ? (
            <p className="body" style={{ color: 'var(--muted)', padding: '24px 0' }}>Log weighted sets to see records.</p>
          ) : (
            <table className="pr-table">
              <thead>
                <tr>
                  <th>Exercise</th>
                  <th>Best set</th>
                  <th>Est. 1RM</th>
                  <th>Sets logged</th>
                  <th>Set on</th>
                </tr>
              </thead>
              <tbody>
                {shown.map((r) => (
                  <tr key={r.name} className={'pr-row' + (r === sel ? ' pr-row--on' : '')} onClick={() => setPicked(r.name)}>
                    <td>
                      <div className="pr-row__name">
                        {r.weight.date >= newCutoff && <span className="caps pr-row__new">New</span>}
                        {r.name}
                      </div>
                      <div className="pr-row__group">{muscleGroupOf(r.name)}</div>
                    </td>
                    <td><b className="pr-row__num">{r.weight.w}</b> kg × {r.weight.reps || '?'}</td>
                    <td>{r.e1rm ? <><b className="pr-row__num pr-row__num--dim">{r.e1rm.v}</b> kg</> : '—'}</td>
                    <td>{r.count}</td>
                    <td>{fmtDate(r.weight.date)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <div>
          {sel && (
            <div className="card">
              <span className="caps">{muscleGroupOf(sel.name)}</span>
              <div className="hero-title" style={{ fontSize: 26, marginTop: 2 }}>{sel.name}</div>
              <div className="pr-detail__stats">
                <div><span className="caps">Best set</span><b>{sel.weight.w}<small> kg × {sel.weight.reps || '?'}</small></b></div>
                <div><span className="caps">Est. 1RM</span><b>{sel.e1rm ? sel.e1rm.v : '—'}<small>{sel.e1rm ? ' kg' : ''}</small></b></div>
              </div>
              <div className="caps" style={{ margin: '14px 0 4px' }}>{e1.length >= 2 ? 'Est. 1RM over time' : 'Heaviest set over time'}</div>
              {trend.length >= 2 ? (
                <LineChart points={trend} unit="kg" height={220} />
              ) : (
                <p style={{ fontSize: 13, color: 'var(--dim)' }}>One more session unlocks the trend.</p>
              )}
              {pts.length >= 2 && (
                <div className="row-between" style={{ fontSize: 13, color: 'var(--muted)', marginTop: 8 }}>
                  <span>First logged {fmtDate(pts[0].date)}</span>
                  <span style={{ color: pts[pts.length - 1].w >= pts[0].w ? 'var(--green)' : 'var(--red)' }}>
                    {pts[pts.length - 1].w >= pts[0].w ? '+' : ''}{Math.round((pts[pts.length - 1].w - pts[0].w) * 10) / 10} kg since
                  </span>
                </div>
              )}
            </div>
          )}
          {next && (
            <div className="card" style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <IconWell icon="local_fire_department" size={38} fill />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600 }}>Next benchmark in reach</div>
                <div style={{ fontSize: 13, color: 'var(--muted)', margin: '2px 0 8px' }}>
                  {next.goal - next.value} more to unlock {next.title.toLowerCase()}
                </div>
                <ProgressLine fraction={next.value / next.goal} height={5} />
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
