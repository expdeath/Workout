import React, { useState } from 'react';
import ActionSheet from '../components/ActionSheet';
import Header from '../components/Header';
import Icon from '../components/Icon';
import { fmtDate, fmtSet, setLogged, cleanWeight, cleanReps, cleanTime, cleanDist } from '../utils/helpers';
import { logMode } from '../utils/stats';

const sid = (s) => s.id || s.date;

export default function History({ history, onBack, onDelete, onUpdate, onOpen, onAddPast }) {
  // every session in the DB, newest first
  const rev = [...history].reverse();
  // per-session ⋯ menu as a bottom sheet: null | { id, mode: 'menu' | 'delete' }
  const [sheet, setSheet] = useState(null);
  const [editing, setEditing] = useState(null); // session id
  const [draft, setDraft] = useState(null);

  const startEdit = (h) => {
    setEditing(sid(h));
    setSheet(null);
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
    // only what this form edits (sets + RPE/pain/feedback), onto the
    // latest copy — a debrief or another device's change that arrived
    // while editing must survive
    const latest = history.find((h) => sid(h) === sid(draft)) || draft;
    onUpdate({ ...latest, log: draft.log, fin: draft.fin });
    setEditing(null);
    setDraft(null);
  };

  return (
    <div className="screen screen--slide-in">
      <Header title="Log" trailing={{ icon: 'plus', label: 'Add past workout', onClick: onAddPast }} />

      {rev.length === 0 && (
        <div className="center-fill">
          <p className="body" style={{ color: 'var(--muted)', textAlign: 'center' }}>
            Nothing logged yet.
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
            <div className="row-between" style={{ alignItems: 'center' }}>
              <span>
                <span className="ex-name">{view.plan.sessionType}</span>
                <span style={{ marginLeft: 8, fontSize: 13, color: 'var(--muted)' }}>{fmtDate(view.date)}</span>
              </span>
              {!isEditing && (
                <button
                  className="icon-btn"
                  style={{ width: 32, height: 28 }}
                  aria-label="Session options"
                  onClick={(e) => {
                    e.stopPropagation();
                    setSheet({ id: sid(h), mode: 'menu' });
                  }}
                >
                  <Icon name="more" size={20} />
                </button>
              )}
            </div>

            {!isEditing && (
              <>
                {(view.plan.exercises || []).map((ex, exI) => {
                  const sets = (view.log?.[exI] || []).filter(setLogged);
                  // exercise left, sets right — one line each
                  return (
                    <div key={exI} className="sum-row">
                      <span>{ex.name}</span>
                      <span>{sets.length ? sets.map(fmtSet).join('  ') : '—'}</span>
                    </div>
                  );
                })}
                {view.fin && (
                  <div style={{ fontSize: 13, color: 'var(--muted)', marginTop: 8 }}>
                    RPE {view.fin.rpe}
                    {view.durationMin ? ` · ${view.durationMin} min` : ''}
                  </div>
                )}
              </>
            )}

            {isEditing && (
              <>
                {(draft.plan.exercises || []).map((ex, exI) => (
                  <div key={exI} style={{ marginTop: 10 }}>
                    <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-body)' }}>
                      {ex.name}
                    </div>
                    {(draft.log?.[exI] || []).map((s, setI) =>
                      logMode(ex.name, draft.plan?.sessionType) === 'check' ? (
                        <div key={setI} className="set-row">
                          <span className="mono set-x" style={{ width: 20 }}>{setI + 1}</span>
                          <span className="set-x" style={{ fontSize: 13 }}>
                            {s.done ? 'Done' : 'Skipped'}
                          </span>
                        </div>
                      ) : logMode(ex.name, draft.plan?.sessionType) === 'cardio' ? (
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
                <div className="q-label" style={{ margin: '14px 0 6px' }}>Session RPE</div>
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

      {sheet && (() => {
        const s = rev.find((h) => sid(h) === sheet.id);
        if (!s) return null;
        return (
          <ActionSheet
            title={`${s.plan?.sessionType || 'Session'} · ${fmtDate(s.date)}`}
            onClose={() => setSheet(null)}
          >
            {sheet.mode === 'menu' && (
              <>
                <button className="action-sheet__item" onClick={() => startEdit(s)}>
                  <Icon name="note" /> Edit
                </button>
                <button
                  className="action-sheet__item action-sheet__item--danger"
                  onClick={() => setSheet({ ...sheet, mode: 'delete' })}
                >
                  <Icon name="trash" /> Delete
                </button>
              </>
            )}
            {sheet.mode === 'delete' && (
              <>
                <p className="action-sheet__note">
                  Delete for good? It's removed from your log, stats and the coach's memory.
                </p>
                <button
                  className="action-sheet__go action-sheet__go--danger"
                  onClick={() => {
                    setSheet(null);
                    onDelete(s);
                  }}
                >
                  Delete
                </button>
              </>
            )}
          </ActionSheet>
        );
      })()}
    </div>
  );
}
