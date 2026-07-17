import React, { useState } from 'react';
import { fmtDate, fmtSet, setLogged, cleanWeight, cleanReps, cleanTime, cleanDist } from '../utils/helpers';
import { isCardio } from '../utils/stats';

const sid = (s) => s.id || s.date;

export default function History({ history, onBack, onDelete, onUpdate, onOpen }) {
  // every session in the DB, newest first
  const rev = [...history].reverse();
  const [menuOpen, setMenuOpen] = useState(null); // session id
  const [confirmDelete, setConfirmDelete] = useState(null);
  const [editing, setEditing] = useState(null); // session id
  const [draft, setDraft] = useState(null);

  const startEdit = (h) => {
    setEditing(sid(h));
    setMenuOpen(null);
    setConfirmDelete(null);
    setDraft(JSON.parse(JSON.stringify(h)));
  };

  const setDraftSet = (exI, setI, field, val) => {
    if (field === 'weight') val = cleanWeight(val);
    if (field === 'reps') val = cleanReps(val);
    if (field === 'time') val = cleanTime(val);
    if (field === 'dist') val = cleanDist(val);
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
          <div
            key={sid(h)}
            className={'card card--animate' + (isEditing ? '' : ' card--tappable')}
            onClick={isEditing ? undefined : () => onOpen?.(h)}
          >
            <div className="row-between">
              <span className="ex-name" style={{ fontSize: 18 }}>
                {view.plan.sessionType}
                {!isEditing && (
                  <span style={{ color: 'var(--dim)', fontSize: 14 }}> ›</span>
                )}
              </span>
              <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span className="mono" style={{ fontSize: 13, color: 'var(--muted)' }}>
                  {fmtDate(view.date)}
                </span>
                {!isEditing && (
                  <button
                    className="menu-btn"
                    aria-label="Session options"
                    onClick={(e) => {
                      e.stopPropagation();
                      setMenuOpen(menuOpen === sid(h) ? null : sid(h));
                      setConfirmDelete(null);
                    }}
                  >
                    ⋯
                  </button>
                )}
              </span>
            </div>

            {menuOpen === sid(h) && (
              <div className="pop-menu" style={{ minWidth: 120 }} onClick={(e) => e.stopPropagation()}>
                <button className="pop-menu__item" onClick={() => startEdit(h)}>
                  Edit
                </button>
                <button
                  className="pop-menu__item pop-menu__item--danger"
                  onClick={() => {
                    setMenuOpen(null);
                    setConfirmDelete(sid(h));
                  }}
                >
                  Delete
                </button>
              </div>
            )}

            {confirmDelete === sid(h) && (
              <div className="remove-confirm" onClick={(e) => e.stopPropagation()}>
                <span>Delete this session for good?</span>
                <button
                  className="remove-confirm__yes"
                  onClick={() => {
                    setConfirmDelete(null);
                    onDelete(h);
                  }}
                >
                  Delete
                </button>
                <button className="remove-confirm__no" onClick={() => setConfirmDelete(null)}>
                  Keep
                </button>
              </div>
            )}

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
                      {sets.length ? sets.map(fmtSet).join('  ') : '—'}
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
                  </div>
                )}
              </>
            )}

            {isEditing && (
              <>
                {(draft.plan.exercises || []).map((ex, exI) => (
                  <div key={exI} style={{ marginTop: 10 }}>
                    <div className="mono" style={{ fontSize: 13, color: 'var(--text-body)' }}>
                      {ex.name}
                    </div>
                    {(draft.log?.[exI] || []).map((s, setI) =>
                      isCardio(ex.name) ? (
                        <div key={setI} className="set-row">
                          <span className="mono set-x" style={{ width: 20 }}>{setI + 1}</span>
                          <input
                            className="set-input"
                            inputMode="decimal"
                            placeholder="min"
                            value={s.time || ''}
                            onChange={(e) => setDraftSet(exI, setI, 'time', e.target.value)}
                          />
                          <span className="set-x">min</span>
                          <input
                            className="set-input"
                            inputMode="decimal"
                            placeholder="km"
                            value={s.dist || ''}
                            onChange={(e) => setDraftSet(exI, setI, 'dist', e.target.value)}
                          />
                          <span className="set-x">km</span>
                        </div>
                      ) : (
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
                      )
                    )}
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
