import React, { useState } from 'react';
import { fmtDate, setLogged, cleanWeight, cleanReps } from '../utils/helpers';

const sid = (s) => s.id || s.date;

export default function History({ history, onBack, onDelete, onUpdate }) {
  // Full history lives in the DB; render only the latest 100 for speed.
  const rev = history.slice(-100).reverse();
  const [confirmDelete, setConfirmDelete] = useState(null);
  const [editing, setEditing] = useState(null); // session id
  const [draft, setDraft] = useState(null);

  const startEdit = (h) => {
    setEditing(sid(h));
    setConfirmDelete(null);
    setDraft(JSON.parse(JSON.stringify(h)));
  };

  const setDraftSet = (exI, setI, field, val) => {
    if (field === 'weight') val = cleanWeight(val);
    if (field === 'reps') val = cleanReps(val);
    const d = JSON.parse(JSON.stringify(draft));
    d.log[exI][setI][field] = val;
    setDraft(d);
  };

  const setFin = (field, val) => {
    setDraft({ ...draft, fin: { ...(draft.fin || {}), [field]: val } });
  };

  const saveEdit = () => {
    onUpdate(draft);
    setEditing(null);
    setDraft(null);
  };

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

      {rev.map((h) => {
        const isEditing = editing === sid(h);
        const view = isEditing ? draft : h;
        return (
          <div key={sid(h)} className="card card--animate">
            <div className="row-between">
              <span className="ex-name" style={{ fontSize: 18 }}>
                {view.plan.sessionType}
              </span>
              <span className="mono" style={{ fontSize: 13, color: 'var(--muted)' }}>
                {fmtDate(view.date)}
              </span>
            </div>

            {!isEditing && (
              <>
                {(view.plan.exercises || []).map((ex, exI) => {
                  const sets = (view.log?.[exI] || []).filter(setLogged);
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
                {view.fin && (
                  <div
                    className="mono"
                    style={{ fontSize: 13, color: 'var(--amber)', marginTop: 8 }}
                  >
                    RPE {view.fin.rpe}/10
                    {view.durationMin ? ` · ${view.durationMin}min` : ''}
                    {view.fin.pain ? ` · ${view.fin.pain}` : ''}
                    {view.fin.feedback ? ` · ${view.fin.feedback}` : ''}
                  </div>
                )}
                {view.debrief && (
                  <p className="body" style={{ fontSize: 13, marginTop: 6, color: 'var(--muted)' }}>
                    🗨 {view.debrief}
                  </p>
                )}
                <div style={{ display: 'flex', gap: 14, marginTop: 10 }}>
                  <button className="ghost-btn" style={{ fontSize: 14 }} onClick={() => startEdit(h)}>
                    Edit
                  </button>
                  <button
                    className="ghost-btn"
                    style={{ fontSize: 14, color: confirmDelete === sid(h) ? 'var(--red)' : undefined }}
                    onClick={() => {
                      if (confirmDelete === sid(h)) {
                        setConfirmDelete(null);
                        onDelete(h);
                      } else {
                        setConfirmDelete(sid(h));
                      }
                    }}
                  >
                    {confirmDelete === sid(h) ? 'Tap again to delete' : 'Delete'}
                  </button>
                </div>
              </>
            )}

            {isEditing && (
              <>
                {(draft.plan.exercises || []).map((ex, exI) => (
                  <div key={exI} style={{ marginTop: 10 }}>
                    <div className="mono" style={{ fontSize: 13, color: 'var(--text-body)' }}>
                      {ex.name}
                    </div>
                    {(draft.log?.[exI] || []).map((s, setI) => (
                      <div key={setI} className="set-row">
                        <span className="mono set-x" style={{ width: 20 }}>{setI + 1}</span>
                        <input
                          className="set-input"
                          inputMode="decimal"
                          placeholder="kg"
                          value={s.weight}
                          onChange={(e) => setDraftSet(exI, setI, 'weight', e.target.value)}
                        />
                        <span className="set-x">×</span>
                        <input
                          className="set-input"
                          inputMode="numeric"
                          placeholder="reps"
                          value={s.reps}
                          onChange={(e) => setDraftSet(exI, setI, 'reps', e.target.value)}
                        />
                      </div>
                    ))}
                  </div>
                ))}
                <div className="mono" style={{ fontSize: 13, marginTop: 12, color: 'var(--muted)' }}>
                  Session RPE
                </div>
                <input
                  className="set-input"
                  inputMode="numeric"
                  value={draft.fin?.rpe ?? ''}
                  onChange={(e) => {
                    const n = e.target.value.replace(/\D/g, '');
                    setFin('rpe', n ? String(Math.min(parseInt(n, 10), 10)) : '');
                  }}
                />
                <input
                  className="input"
                  placeholder="Pain (empty = none)"
                  value={draft.fin?.pain ?? ''}
                  onChange={(e) => setFin('pain', e.target.value)}
                />
                <input
                  className="input"
                  placeholder="Feedback"
                  value={draft.fin?.feedback ?? ''}
                  onChange={(e) => setFin('feedback', e.target.value)}
                />
                <div style={{ display: 'flex', gap: 10, marginTop: 12 }}>
                  <button className="big-btn" style={{ marginTop: 0, padding: 12, fontSize: 16 }} onClick={saveEdit}>
                    Save changes
                  </button>
                  <button
                    className="ghost-btn"
                    onClick={() => { setEditing(null); setDraft(null); }}
                  >
                    Cancel
                  </button>
                </div>
              </>
            )}
          </div>
        );
      })}
      <div style={{ height: 24 }} />
    </div>
  );
}
