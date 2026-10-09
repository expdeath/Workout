import React, { useState } from 'react';
import ActionSheet from '../components/ActionSheet';
import Icon from '../components/Icon';
import { TabHeader, SectionHead, ProgressLine, IconWell, PageHero, StatusPill, useDesktop } from '../components/Shell';
import { fmtDate, fmtSet, setLogged, cleanWeight, cleanReps, cleanTime, cleanDist, todayStr } from '../utils/helpers';
import { logMode, sessionVolume, weekStats, mondayOf, muscleGroupOf } from '../utils/stats';
import { weeklyTarget } from '../utils/dashboard';
import { getAISettings } from '../utils/storage';

const sid = (s) => s.id || s.date;

const DAY = 86400000;
const isoOf = (d) => new Date(d.getTime() + 12 * 3600000).toISOString().slice(0, 10);
/** Every exercise logged as time/distance (quick cardio, a run…). */
const isCardio = (h) =>
  (h.plan?.exercises || []).length > 0 && h.plan.exercises.every((e) => logMode(e.name, h.plan.sessionType) === 'cardio');
const cardioIcon = (name = '') =>
  /cycl|ride|bike/i.test(name) ? 'ride' : /hike/i.test(name) ? 'hike' : /walk/i.test(name) ? 'walk' : 'run';

export default function History({ history, onDelete, onUpdate, onOpen, onAddPast }) {
  const desktop = useDesktop();
  const [selId, setSelId] = useState(null); // desktop: the session shown on the right
  // every session in the DB, newest first
  const rev = [...history].reverse();
  const [filter, setFilter] = useState('all'); // all | strength | cardio
  const [weekOffset, setWeekOffset] = useState(0);
  const [day, setDay] = useState(null);
  // the three newest sessions start expanded
  const [open, setOpen] = useState(() => new Set(rev.slice(0, 3).map(sid)));
  const toggle = (id) => {
    const n = new Set(open);
    n.has(id) ? n.delete(id) : n.add(id);
    setOpen(n);
  };
  const target = weeklyTarget(getAISettings());
  const { thisWeek } = weekStats(history, target);
  const pct = Math.min(100, Math.round((thisWeek / target) * 100));
  const monday = new Date(mondayOf(todayStr()) + 'T00:00:00');
  const weekStart = new Date(monday.getTime() + weekOffset * 7 * DAY);
  const logged = new Set(history.map((h) => h.date));
  const shown = rev.filter((h) => (!day || h.date === day) && (filter === 'all' || (filter === 'cardio') === isCardio(h)));
  const weekNo = (() => {
    const d = new Date(Date.UTC(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 3));
    const y = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
    return 1 + Math.round(((d - y) / DAY - 3 + ((y.getUTCDay() + 6) % 7)) / 7);
  })();
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

  // per-session ⋯ menu: Edit / Delete (bottom sheet on phones, a dialog on desktop)
  const actionSheet = sheet && (() => {
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
              <Icon name="edit" /> Edit
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
  })();

  // the edit form: sets + RPE/pain/feedback of the session being edited
  const editFields = () => (
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
  );

  // ── desktop: filters + session list on the left, the picked session on the right ──
  if (desktop) {
    const sel = shown.find((h) => sid(h) === selId) || shown[0];
    const isEditing = sel && editing === sid(sel);
    const weekVolume = history.filter((h) => h.date >= isoOf(monday)).reduce((a, h) => a + sessionVolume(h), 0);
    return (
      <div className="screen screen--fade-in">
        <TabHeader title="Log" />
        <PageHero
          kicker={`${weekStart.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })} · Week ${weekNo}`}
          title="Workout log"
          sub={`${history.length} sessions logged · ${thisWeek} of ${target} this week · ${weekVolume.toLocaleString()} kg lifted this week`}
        >
          <button className="big-btn" onClick={onAddPast}>
            <Icon name="add" size={20} /> Log workout
          </button>
        </PageHero>

        <div className="log-desk">
          <div>
            <div className="card">
              <div className="week-strip" style={{ marginTop: 0, padding: 0 }}>
                <button className="icon-btn" style={{ width: 24 }} aria-label="Previous week" onClick={() => setWeekOffset(weekOffset - 1)}>
                  <Icon name="back" size={20} />
                </button>
                {Array.from({ length: 7 }, (_, i) => {
                  const d = new Date(weekStart.getTime() + i * DAY);
                  const iso = isoOf(d);
                  return (
                    <button
                      key={iso}
                      className={'week-strip__day' + (day === iso ? ' week-strip__day--on' : '') + (iso === todayStr() ? ' week-strip__day--today' : '')}
                      disabled={iso > todayStr()}
                      onClick={() => setDay(day === iso ? null : iso)}
                    >
                      <span className="caps" style={{ fontSize: 11, color: 'var(--dim)' }}>{d.toLocaleDateString(undefined, { weekday: 'narrow' })}</span>
                      <span className="week-strip__num">{d.getDate()}</span>
                      <span className="week-strip__dot" style={{ background: logged.has(iso) ? 'var(--amber)' : 'transparent' }} />
                    </button>
                  );
                })}
                <button className="icon-btn" style={{ width: 24, visibility: weekOffset < 0 ? 'visible' : 'hidden' }} aria-label="Next week" onClick={() => setWeekOffset(Math.min(weekOffset + 1, 0))}>
                  <Icon name="right" size={20} />
                </button>
              </div>
              <div style={{ margin: '14px 0 6px' }}>
                <div className="row-between">
                  <span className="caps">Weekly target</span>
                  <span className="caps" style={{ fontSize: 12, color: pct >= 100 ? 'var(--green)' : 'var(--amber-text)' }}>{thisWeek} / {target} · {pct}%</span>
                </div>
                <div style={{ marginTop: 8 }}><ProgressLine fraction={pct / 100} color={pct >= 100 ? 'var(--green)' : 'var(--amber)'} height={6} /></div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 8, margin: '16px 0 8px', alignItems: 'center' }}>
              {[['all', 'All'], ['strength', 'Strength'], ['cardio', 'Cardio']].map(([v, l]) => (
                <button key={v} className={'chip' + (filter === v ? ' chip-on' : '')} onClick={() => setFilter(v)}>{l}</button>
              ))}
              <span className="caps" style={{ marginLeft: 'auto', color: 'var(--muted)', fontSize: 12 }}>
                {day ? <button className="chip" onClick={() => setDay(null)}>Clear day</button> : `${shown.length} sessions`}
              </span>
            </div>

            {shown.length === 0 && (
              <p className="body" style={{ color: 'var(--muted)', textAlign: 'center', padding: '40px 0' }}>
                {rev.length ? 'No sessions here.' : 'Nothing logged yet.'}
              </p>
            )}
            <div className="log-list">
              {shown.map((h) => {
                const cardio = isCardio(h);
                const sets = h.log.flat().filter(setLogged);
                const km = sets.reduce((a, x) => a + (parseFloat(x.dist) || 0), 0);
                const name = cardio ? h.plan.exercises[0]?.name || h.plan.sessionType : h.plan.title || h.plan.sessionType;
                return (
                  <button key={sid(h)} className={'log-item' + (h === sel ? ' log-item--on' : '')} onClick={() => setSelId(sid(h))}>
                    <IconWell icon={cardio ? cardioIcon(name) : 'dumbbell'} tint={cardio ? 'var(--green)' : 'var(--amber-text)'} size={34} />
                    <span className="log-item__text">
                      <span className="log-item__title">{name}</span>
                      <span className="log-item__sub">{fmtDate(h.date)}{h.durationMin ? ` · ${h.durationMin} min` : ''}</span>
                    </span>
                    <span className="log-item__val">
                      <b>{cardio ? (km ? `${Math.round(km * 10) / 10} km` : `${sets.reduce((a, x) => a + (parseFloat(x.time) || 0), 0)} min`) : `${(sessionVolume(h) / 1000).toFixed(1)}t`}</b>
                      {h.fin?.rpe ? <span className="caps">RPE {h.fin.rpe}</span> : null}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          <div>
            {sel && (
              <div className="card">
                <div className="row-between" style={{ alignItems: 'flex-start', gap: 16 }}>
                  <div style={{ minWidth: 0 }}>
                    <span className="caps" style={{ color: 'var(--amber-text)' }}>{fmtDate(sel.date)}</span>
                    <div className="hero-title" style={{ fontSize: 34, marginTop: 4 }}>
                      {isCardio(sel) ? sel.plan.exercises[0]?.name || sel.plan.sessionType : sel.plan.title || sel.plan.sessionType}
                    </div>
                  </div>
                  {!isEditing && (
                    <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
                      <button className="small-btn" onClick={() => onOpen?.(sel)}>
                        <Icon name="chat" size={16} /> Ask the coach
                      </button>
                      <button className="outline-btn" onClick={() => startEdit(sel)}>
                        <Icon name="edit" size={16} /> Edit
                      </button>
                      <button className="outline-btn outline-btn--danger" onClick={() => setSheet({ id: sid(sel), mode: 'delete' })}>
                        <Icon name="trash" size={16} /> Delete
                      </button>
                    </div>
                  )}
                </div>

                {isEditing ? (
                  <div style={{ maxWidth: 560 }}>{editFields()}</div>
                ) : (
                  <>
                    <div className="stat-strip" style={{ marginTop: 16 }}>
                      <span><span className="caps">Volume</span><b>{sessionVolume(sel).toLocaleString()} kg</b></span>
                      <span><span className="caps">Sets</span><b>{sel.log.flat().filter(setLogged).length}</b></span>
                      <span><span className="caps">Duration</span><b>{sel.durationMin ? `${sel.durationMin} min` : '—'}</b></span>
                      <span><span className="caps">Effort</span><b style={{ color: 'var(--amber-text)' }}>{sel.fin?.rpe ? `RPE ${sel.fin.rpe}` : '—'}</b></span>
                    </div>
                    <table className="pr-table log-sets">
                      <thead>
                        <tr><th>Exercise</th><th>Sets</th><th>Best</th></tr>
                      </thead>
                      <tbody>
                        {(sel.plan.exercises || []).map((ex, exI) => {
                          const all = sel.log?.[exI] || [];
                          const done = all.filter(setLogged);
                          const best = [...done].sort((a, b) => (parseFloat(b.weight) || 0) - (parseFloat(a.weight) || 0))[0];
                          return (
                            <tr key={exI}>
                              <td>
                                <div className="pr-row__name">{ex.name}</div>
                                <div className="pr-row__group">{muscleGroupOf(ex.name)}</div>
                              </td>
                              <td>
                                <div className="set-chips">
                                  {all.length ? all.map((x, k) => (
                                    <span key={k} className={'set-chip' + (setLogged(x) ? '' : ' set-chip--skip')}>{fmtSet(x)}</span>
                                  )) : '—'}
                                </div>
                              </td>
                              <td><b className="pr-row__num">{best ? fmtSet(best) : '—'}</b></td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                    {(sel.fin?.pain || sel.fin?.feedback) && (
                      <div className="log-notes">
                        {sel.fin.pain && <div><StatusPill text="Pain" color="var(--red)" dot={false} /> {sel.fin.pain}</div>}
                        {sel.fin.feedback && <div><span className="caps" style={{ marginRight: 8 }}>Notes</span>{sel.fin.feedback}</div>}
                      </div>
                    )}
                  </>
                )}
              </div>
            )}
          </div>
        </div>
        {actionSheet}
      </div>
    );
  }

  return (
    <div className="screen screen--slide-in">
      <TabHeader title="Log" />

      <div className="row-between" style={{ alignItems: 'center' }}>
        <span>
          <span className="caps" style={{ color: 'var(--amber-text)', fontSize: 14 }}>
            {weekStart.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}
          </span>
          <span style={{ marginLeft: 8, fontSize: 13, color: 'var(--muted)' }}>Week {weekNo}</span>
        </span>
        <button className="outline-btn" aria-label="Add past workout" onClick={onAddPast}>
          <Icon name="add" size={18} /> Log workout
        </button>
      </div>

      <div className="week-strip">
        <button className="icon-btn" style={{ width: 24 }} aria-label="Previous week" onClick={() => setWeekOffset(weekOffset - 1)}>
          <Icon name="back" size={20} />
        </button>
        {Array.from({ length: 7 }, (_, i) => {
          const d = new Date(weekStart.getTime() + i * DAY);
          const iso = isoOf(d);
          const future = iso > todayStr();
          return (
            <button
              key={iso}
              className={'week-strip__day' + (day === iso ? ' week-strip__day--on' : '') + (iso === todayStr() ? ' week-strip__day--today' : '')}
              disabled={future}
              onClick={() => setDay(day === iso ? null : iso)}
            >
              <span className="caps" style={{ fontSize: 11, color: 'var(--dim)' }}>{d.toLocaleDateString(undefined, { weekday: 'narrow' })}</span>
              <span className="week-strip__num">{d.getDate()}</span>
              <span className="week-strip__dot" style={{ background: logged.has(iso) ? 'var(--amber)' : 'transparent' }} />
            </button>
          );
        })}
        <button className="icon-btn" style={{ width: 24, visibility: weekOffset < 0 ? 'visible' : 'hidden' }} aria-label="Next week" onClick={() => setWeekOffset(Math.min(weekOffset + 1, 0))}>
          <Icon name="right" size={20} />
        </button>
      </div>

      <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
        {[['all', 'All'], ['strength', 'Strength'], ['cardio', 'Cardio']].map(([v, l]) => (
          <button key={v} className={'chip' + (filter === v ? ' chip-on' : '')} onClick={() => setFilter(v)}>{l}</button>
        ))}
        {day && <button className="chip" style={{ marginLeft: 'auto' }} onClick={() => setDay(null)}>Clear day</button>}
      </div>

      <div className="card">
        <div className="row-between">
          <span className="caps">Weekly target</span>
          <span className="caps" style={{ fontSize: 12, color: pct >= 100 ? 'var(--green)' : 'var(--amber-text)' }}>{pct}% complete</span>
        </div>
        <div style={{ margin: '8px 0' }}><ProgressLine fraction={pct / 100} color={pct >= 100 ? 'var(--green)' : 'var(--amber)'} height={7} /></div>
        <div className="row-between" style={{ fontSize: 12.5, color: 'var(--muted)' }}>
          <span>{thisWeek} of {target} sessions finished</span>
          <span>{thisWeek >= target ? 'Target hit' : `${target - thisWeek} to go`}</span>
        </div>
      </div>

      {shown.length === 0 && (
        <p className="body" style={{ color: 'var(--muted)', textAlign: 'center', padding: '40px 0' }}>
          {rev.length ? 'No sessions here.' : 'Nothing logged yet.'}
        </p>
      )}

      {shown.map((h) => {
        const isEditing = editing === sid(h);
        const view = isEditing ? draft : h;
        const menuBtn = (
          <button
            className="icon-btn"
            style={{ width: 30, height: 30 }}
            aria-label="Session options"
            onClick={(e) => {
              e.stopPropagation();
              setSheet({ id: sid(h), mode: 'menu' });
            }}
          >
            <Icon name="more" size={20} />
          </button>
        );
        if (!isEditing && isCardio(h)) {
          const sets = h.log.flat().filter(setLogged);
          const km = sets.reduce((a, s) => a + (parseFloat(s.dist) || 0), 0);
          const min = sets.reduce((a, s) => a + (parseFloat(s.time) || 0), 0);
          const name = h.plan.exercises[0]?.name || h.plan.sessionType;
          return (
            <div key={sid(h)} className="card card--animate card--tappable" onClick={() => onOpen?.(h)}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <IconWell icon={cardioIcon(name)} tint="var(--green)" />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: 17 }}>{name}</div>
                  <div style={{ fontSize: 13, color: 'var(--muted)' }}>{fmtDate(h.date)}{min ? ` · ${min} min` : ''}</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div className="hero-title" style={{ fontSize: 20 }}>{km ? `${Math.round(km * 10) / 10} km` : `${min} min`}</div>
                  {h.fin && <div className="caps" style={{ fontSize: 11, color: 'var(--green)' }}>RPE {h.fin.rpe}</div>}
                </div>
                {menuBtn}
              </div>
            </div>
          );
        }
        const isOpen = open.has(sid(h));
        const setsDone = (view.log || []).flat().filter(setLogged).length;
        return (
          <div
            key={sid(h)}
            className={'card card--animate' + (isEditing ? '' : ' card--tappable')}
            onClick={isEditing ? undefined : () => onOpen?.(h)}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <IconWell icon="dumbbell" />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 700, fontSize: 17 }}>{view.plan.sessionType}</div>
                <div style={{ fontSize: 13, color: 'var(--muted)' }}>{fmtDate(view.date)}{view.durationMin ? ` · ${view.durationMin} min` : ''}</div>
              </div>
              {!isEditing && (
                <button
                  className="icon-btn"
                  style={{ width: 30, height: 30, borderRadius: '50%', background: 'var(--bg-high)' }}
                  aria-label={isOpen ? 'Collapse' : 'Expand'}
                  onClick={(e) => {
                    e.stopPropagation();
                    toggle(sid(h));
                  }}
                >
                  <Icon name="down" size={20} style={{ transform: isOpen ? 'rotate(180deg)' : 'none', transition: 'transform 0.2s' }} />
                </button>
              )}
              {!isEditing && menuBtn}
            </div>

            {!isEditing && (
              <>
                <div className="stat-strip">
                  <span><span className="caps">Volume</span><b>{sessionVolume(view).toLocaleString()} kg</b></span>
                  <span><span className="caps">Sets</span><b>{setsDone}</b></span>
                  <span><span className="caps">Effort</span><b style={{ color: 'var(--amber-text)' }}>{view.fin ? `RPE ${view.fin.rpe}` : '—'}</b></span>
                </div>
                {isOpen &&
                  (view.plan.exercises || []).map((ex, exI) => {
                    const sets = (view.log?.[exI] || []).filter(setLogged);
                    const best = [...sets].sort((a, b) => (parseFloat(b.weight) || 0) - (parseFloat(a.weight) || 0))[0];
                    return (
                      <div key={exI} className="ex-row" aria-label={`${ex.name}: ${sets.length ? sets.map(fmtSet).join('  ') : '—'}`}>
                        <span className="ex-row__dot" />
                        <span className="ex-row__name">{ex.name}</span>
                        <span className="ex-row__val">{best ? (best.weight || best.reps ? `${best.weight || '—'}kg × ${best.reps || '?'}` : fmtSet(best)) : '—'}</span>
                      </div>
                    );
                  })}
              </>
            )}

            {isEditing && editFields()}
          </div>
        );
      })}

      {actionSheet}
    </div>
  );
}
