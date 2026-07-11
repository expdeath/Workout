import React from 'react';
import { fmtDate } from '../utils/helpers';
import { weekStats } from '../utils/stats';

const WEEK_MS = 7 * 86400000;

export default function Home({ todayPlan, history, syncInfo, weeklyReview, onStart, onQuickStart, onResume, onHistory, onSettings, onProgress }) {
  const last = history[history.length - 1];
  const doneToday = todayPlan && todayPlan.finished;
  const inProgress = todayPlan && !todayPlan.finished;
  const { thisWeek, streak } = weekStats(history);
  const showReview = weeklyReview?.text && Date.now() - (weeklyReview.at || 0) < WEEK_MS;

  return (
    <div className="screen screen--fade-in">
      <header className="header">
        <div className="brand-sm">COACH</div>
        <div className="header__actions">
          <button className="ghost-btn" onClick={onSettings}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="3"/>
              <path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>
            </svg>
          </button>
          <button className="ghost-btn" onClick={onProgress}>Stats</button>
          <button className="ghost-btn" onClick={onHistory}>Log</button>
        </div>
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
            ? 'Session done.'
            : inProgress
            ? 'Session in progress'
            : 'Ready when you are.'}
        </h1>
        <p className="subtitle">
          {doneToday
            ? `${todayPlan.plan.sessionType} logged. Recovery feeds tomorrow's plan.`
            : inProgress
            ? `${todayPlan.plan.sessionType} — pick up where you left off.`
            : '60-second check-in. The plan, the weights, the timing — handled.'}
        </p>
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
            <div className="stat-tile__label">Week streak (≥3)</div>
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
        <>
          <button className="big-btn" onClick={onStart}>
            {doneToday ? 'Plan another session' : 'Start check-in'}
          </button>
          <button className="quick-btn" onClick={onQuickStart}>
            ⚡ Quick start — normal day, skip the questions
          </button>
        </>
      )}

      {last && (
        <div className="card card--animate">
          <div className="card__label">Last session</div>
          <div className="row-between">
            <span className="mono">{fmtDate(last.date)}</span>
            <span className="mono" style={{ color: 'var(--amber)' }}>
              {last.plan.sessionType}
            </span>
          </div>
          {last.fin && (
            <div className="mono card__detail">
              Session RPE {last.fin.rpe}/10
              {last.fin.pain ? ` · pain: ${last.fin.pain}` : ''}
            </div>
          )}
          {last.debrief && (
            <p className="body" style={{ marginTop: 10, color: 'var(--text-body)' }}>
              🗨 {last.debrief}
            </p>
          )}
        </div>
      )}

      {showReview && (
        <div className="card card--animate">
          <div className="card__label">Weekly review</div>
          <div className="mono card__detail" style={{ marginTop: 0 }}>
            {weeklyReview.count} sessions
            {weeklyReview.progressions && weeklyReview.progressions !== 'none'
              ? ` · up: ${weeklyReview.progressions}`
              : ''}
          </div>
          <p className="body" style={{ marginTop: 8 }}>{weeklyReview.text}</p>
        </div>
      )}

      <div className="foot-note">
        Tip: paste today's Apple Health numbers during check-in (sleep, HRV,
        resting HR, steps) — the coach reads them.
      </div>

      {syncInfo && (
        <div className="foot-note mono" style={{ marginTop: 4 }}>
          {syncInfo.state === 'syncing'
            ? '☁ syncing…'
            : syncInfo.state === 'ok'
            ? `☁ synced ${new Date(syncInfo.at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} · ${syncInfo.sessions} sessions in cloud`
            : `☁ sync error — ${syncInfo.message}`}
        </div>
      )}
    </div>
  );
}
