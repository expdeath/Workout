import React from 'react';
import { fmtDate } from '../utils/helpers';

export default function Home({ todayPlan, history, syncInfo, onStart, onResume, onHistory, onSettings }) {
  const last = history[history.length - 1];
  const doneToday = todayPlan && todayPlan.finished;
  const inProgress = todayPlan && !todayPlan.finished;

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

      {inProgress ? (
        <button className="big-btn" onClick={onResume}>
          Resume {todayPlan.plan.sessionType}
        </button>
      ) : (
        <button className="big-btn" onClick={onStart}>
          {doneToday ? 'Plan another session' : 'Start check-in'}
        </button>
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
