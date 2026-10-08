import React, { useState } from 'react';
import { fmtDate } from '../utils/helpers';
import { weekStats, deloadSignal } from '../utils/stats';
import { getAccount } from '../utils/account';
import QuickCardioSheet from '../components/QuickCardioSheet';
import Icon from '../components/Icon';

const WEEK_MS = 7 * 86400000;

export default function Home({ todayPlan, history, syncInfo, weeklyReview, monthlyReport, onStart, onQuickStart, onResume, onQuickCardio, onOpenSession }) {
  // first name from the redeemed invite — absent on pre-account installs
  const name = getAccount()?.name?.split(' ')[0];
  // Run / ride / walk, logged straight to history — apart from
  // whatever the AI-generated plan is doing today
  const [quickCardio, setQuickCardio] = useState(null); // null | 'run' | 'cycle' | 'walk'
  const last = history[history.length - 1];
  const doneToday = todayPlan && todayPlan.finished;
  const inProgress = todayPlan && !todayPlan.finished;
  const { thisWeek, streak } = weekStats(history);
  const showReview = weeklyReview?.text && Date.now() - (weeklyReview.at || 0) < WEEK_MS;
  const showMonthly = monthlyReport?.text && Date.now() - (monthlyReport.at || 0) < 10 * 86400000;
  const deload = deloadSignal(history);

  return (
    <div className="screen screen--fade-in">
      <header className="header">
        <div className="brand-sm">COACH</div>
      </header>

      <div className="hero">
        <div className="eyebrow">
          {new Date().toLocaleDateString(undefined, {
            weekday: 'long',
            month: 'long',
            day: 'numeric',
          })}
        </div>
        <h1 className="h1">
          {doneToday
            ? name
              ? `Nice work, ${name}.`
              : 'Session done.'
            : inProgress
            ? `${todayPlan.plan.sessionType} in progress`
            : name
            ? `Ready, ${name}?`
            : 'Ready?'}
        </h1>
      </div>

      {history.length > 0 && (
        <div className="stat-row">
          <div className="stat-tile">
            <div className="stat-tile__label">This week</div>
            <div className="stat-tile__value">
              {thisWeek} <span className="stat-tile__unit">sessions</span>
            </div>
          </div>
          <div className="stat-tile">
            <div className="stat-tile__label">Streak</div>
            <div className="stat-tile__value">
              {streak} <span className="stat-tile__unit">wks</span>
            </div>
          </div>
        </div>
      )}

      {inProgress ? (
        <button className="big-btn" onClick={onResume}>
          Resume {todayPlan.plan.sessionType}
        </button>
      ) : (
        <button className="big-btn" onClick={onStart}>
          {doneToday ? 'Plan another session' : 'Start check-in'}
        </button>
      )}

      {/* one row of shortcuts: skip the check-in, or log cardio directly */}
      <div className="shortcut-row">
        {!inProgress && (
          <button className="shortcut shortcut--accent" onClick={onQuickStart}>
            <span className="shortcut__icon"><Icon name="bolt" size={20} /></span>
            Quick start
          </button>
        )}
        {[['run', '🏃', 'Run'], ['cycle', '🚴', 'Ride'], ['walk', '🚶', 'Walk'], ['hike', '🥾', 'Hike']].map(([kind, emoji, label]) => (
          <button key={kind} className="shortcut" aria-label={label} onClick={() => setQuickCardio(kind)}>
            <span className="shortcut__icon" aria-hidden="true">{emoji}</span>
            {label}
          </button>
        ))}
      </div>

      {quickCardio && (
        <QuickCardioSheet
          kind={quickCardio}
          onClose={() => setQuickCardio(null)}
          onSave={onQuickCardio}
        />
      )}

      {deload && (
        <div className="card card--animate deload-card">
          <div className="card__label" style={{ color: 'var(--amber)' }}>
            Deload suggested
          </div>
          <p className="body">{deload.reason}</p>
        </div>
      )}

      {last && (
        <div className="card card--animate card--tappable" onClick={() => onOpenSession(last)}>
          <div className="row-between">
            <span>
              <span className="ex-name">{last.plan.sessionType}</span>
              <span style={{ marginLeft: 8, fontSize: 13, color: 'var(--muted)' }}>{fmtDate(last.date)}</span>
            </span>
            {last.fin && (
              <span style={{ fontSize: 13, fontWeight: 500, color: 'var(--amber)' }}>RPE {last.fin.rpe}</span>
            )}
          </div>
          {last.debrief && (
            <p className="body clamp" style={{ '--lines': 3, marginTop: 6, color: 'var(--muted)' }}>
              {last.debrief}
            </p>
          )}
        </div>
      )}

      {showMonthly && (
        <div className="card card--animate">
          <div className="card__label" style={{ color: 'var(--amber)' }}>
            Monthly report ·{' '}
            {new Date(monthlyReport.month + '-15').toLocaleDateString(undefined, {
              month: 'long',
            })}
          </div>
          <div className="card__detail" style={{ marginTop: 0 }}>
            {monthlyReport.sum?.count} sessions · {monthlyReport.sum?.volume?.toLocaleString()}kg lifted
          </div>
          <Clamped text={monthlyReport.text} />
        </div>
      )}

      {showReview && (
        <div className="card card--animate">
          <div className="card__label">Weekly review</div>
          <Clamped text={weeklyReview.text} />
        </div>
      )}

      {/* sync status lives in Settings; Home only speaks up when it fails */}
      {syncInfo?.state === 'error' && (
        <div className="foot-note" style={{ color: 'var(--red)' }}>
          Sync error — {syncInfo.message}
        </div>
      )}
    </div>
  );
}

// Long coach text clamped to four lines; tap to read the rest.
function Clamped({ text }) {
  const [open, setOpen] = useState(false);
  return (
    <p
      className={`body clamp${open ? ' clamp--open' : ''}`}
      style={{ marginTop: 8 }}
      onClick={() => setOpen(!open)}
    >
      {text}
    </p>
  );
}
