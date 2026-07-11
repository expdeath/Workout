import React from 'react';
import { fmtDate, setLogged } from '../utils/helpers';

export default function History({ history, onBack }) {
  // Full history lives in the DB; render only the latest 100 for speed.
  const rev = history.slice(-100).reverse();

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onBack}>Home</button>
        <div className="brand-sm">LOG</div>
        <div />
      </header>

      {rev.length === 0 && (
        <div className="center-fill">
          <p className="body" style={{ color: 'var(--muted)', textAlign: 'center' }}>
            Nothing logged yet.
            <br />
            Your first session will show up here — and every one after it makes
            the coach smarter.
          </p>
        </div>
      )}

      {rev.map((h, i) => (
        <div key={i} className="card card--animate">
          <div className="row-between">
            <span className="ex-name" style={{ fontSize: 18 }}>
              {h.plan.sessionType}
            </span>
            <span className="mono" style={{ fontSize: 13, color: 'var(--muted)' }}>
              {fmtDate(h.date)}
            </span>
          </div>
          {(h.plan.exercises || []).map((ex, exI) => {
            const sets = (h.log?.[exI] || []).filter(setLogged);
            return (
              <div
                key={exI}
                className="mono"
                style={{ fontSize: 13, color: 'var(--muted)', marginTop: 6 }}
              >
                {ex.name}:{' '}
                {sets.length
                  ? sets
                      .map((s) => `${s.weight || '?'}×${s.reps || '?'}`)
                      .join('  ')
                  : '—'}
              </div>
            );
          })}
          {h.fin && (
            <div
              className="mono"
              style={{ fontSize: 13, color: 'var(--amber)', marginTop: 8 }}
            >
              RPE {h.fin.rpe}/10
              {h.fin.pain ? ` · ${h.fin.pain}` : ''}
              {h.fin.feedback ? ` · ${h.fin.feedback}` : ''}
            </div>
          )}
          {h.debrief && (
            <p className="body" style={{ fontSize: 13, marginTop: 6, color: 'var(--muted)' }}>
              🗨 {h.debrief}
            </p>
          )}
        </div>
      ))}
      <div style={{ height: 24 }} />
    </div>
  );
}
