import React, { useState } from 'react';
import { fmtDate, daysAgoStr } from '../utils/helpers';
import { prRecords, exerciseSeries, weekStats, sessionVolume, muscleGroupOf } from '../utils/stats';
import { getAISettings } from '../utils/storage';
import { milestones, keyMilestones, nextBenchmark, weeklyTarget } from '../utils/dashboard';
import { LineChart } from '../components/Charts';
import { TabHeader, StatusPill, SectionHead, ProgressLine, IconWell } from '../components/Shell';
import Icon from '../components/Icon';

/** The honor roll (milestones unlocked), lifetime stats, the milestone
 *  grid with progress, personal records (tap one for its est. 1RM
 *  trend) and the next benchmark in reach. The iOS RecordsView mirrors this. */
export default function Records({ history }) {
  const records = prRecords(history)
    .filter((r) => r.weight)
    .sort((a, b) => (a.weight.date < b.weight.date ? 1 : -1));
  const series = exerciseSeries(history);
  const [openEx, setOpenEx] = useState(null); // exercise name or null
  const [showAll, setShowAll] = useState(false);
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
        const isOpen = openEx === r.name;
        const isNew = r.weight.date >= newCutoff;
        const pts = series.find((e) => e.name === r.name)?.points || [];
        return (
          <div key={r.name} className="pr-card" onClick={() => setOpenEx(isOpen ? null : r.name)}>
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
