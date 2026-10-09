import React, { useEffect, useMemo, useRef, useState } from 'react';
import Icon from './Icon';
import { PanelSheet, IconWell, useShell } from './Shell';
import { prRecords, muscleGroupOf, logMode } from '../utils/stats';
import { fmtDate } from '../utils/helpers';
import { listWorkouts, daysLabel } from '../utils/workouts';

// Search across the account: exercises (→ their record), logged
// sessions (→ the session) and saved workouts (→ the editor).
// Desktop: a box in the top nav. Phones: the header's search button
// opens it in a sheet.

const sessionName = (s) =>
  (s.plan?.exercises || []).every((e) => logMode(e.name, s.plan.sessionType) === 'cardio')
    ? s.plan.exercises[0]?.name || s.plan.sessionType
    : s.plan?.title || s.plan?.sessionType || 'Session';

function useResults(q, history) {
  const records = useMemo(() => prRecords(history), [history]);
  const names = useMemo(
    () => [...new Set(history.flatMap((s) => (s.plan?.exercises || []).map((e) => e?.name?.trim()).filter(Boolean)))],
    [history]
  );
  const term = q.trim().toLowerCase();
  if (term.length < 2) return null;
  const has = (t) => String(t || '').toLowerCase().includes(term);

  const exercises = names
    .filter(has)
    .map((name) => ({ name, rec: records.find((r) => r.name.toLowerCase() === name.toLowerCase()) }))
    .sort((a, b) => (b.rec?.count || 0) - (a.rec?.count || 0))
    .slice(0, 5);
  const sessions = [...history]
    .reverse()
    .filter(
      (s) =>
        has(sessionName(s)) ||
        has(s.plan?.sessionType) ||
        has(s.date) ||
        has(fmtDate(s.date)) ||
        has(s.fin?.feedback) ||
        (s.plan?.exercises || []).some((e) => has(e?.name))
    )
    .slice(0, 6);
  const workouts = listWorkouts()
    .filter((w) => has(w.name) || has(w.trainer) || w.exercises.some((e) => has(e.name)))
    .slice(0, 4);
  return { exercises, sessions, workouts, count: exercises.length + sessions.length + workouts.length };
}

function Results({ res, onPick }) {
  const { openSession, openRecord, openWorkouts } = useShell();
  if (!res) return <p className="search__hint">Search exercises, workouts and your log — e.g. “squat”, “push”, “Sept”.</p>;
  if (!res.count) return <p className="search__hint">Nothing matches.</p>;
  const go = (fn) => () => {
    onPick();
    fn();
  };
  return (
    <>
      {res.exercises.length > 0 && <div className="caps search__group">Exercises</div>}
      {res.exercises.map(({ name, rec }) => (
        <button key={name} className="search__row" onClick={go(() => openRecord(name))}>
          <IconWell icon="emoji_events" size={30} />
          <span className="search__text">
            <span className="search__title">{name}</span>
            <span className="search__sub">{muscleGroupOf(name)}{rec?.count ? ` · ${rec.count} sets logged` : ''}</span>
          </span>
          {rec?.weight && <span className="caps search__val">{rec.weight.w} kg × {rec.weight.reps || '?'}</span>}
        </button>
      ))}
      {res.workouts.length > 0 && <div className="caps search__group">My workouts</div>}
      {res.workouts.map((w) => (
        <button key={w.id} className="search__row" onClick={go(() => openWorkouts(w.id))}>
          <IconWell icon="edit_note" size={30} />
          <span className="search__text">
            <span className="search__title">{w.name}</span>
            <span className="search__sub">{[w.source === 'trainer' ? w.trainer || 'Trainer' : 'Mine', daysLabel(w), `${w.exercises.length} exercises`].filter(Boolean).join(' · ')}</span>
          </span>
        </button>
      ))}
      {res.sessions.length > 0 && <div className="caps search__group">Sessions</div>}
      {res.sessions.map((s) => (
        <button key={s.id || s.date} className="search__row" onClick={go(() => openSession(s))}>
          <IconWell icon="fitness_center" size={30} />
          <span className="search__text">
            <span className="search__title">{sessionName(s)}</span>
            <span className="search__sub">{fmtDate(s.date)}{s.durationMin ? ` · ${s.durationMin} min` : ''}{s.fin?.rpe ? ` · RPE ${s.fin.rpe}` : ''}</span>
          </span>
        </button>
      ))}
    </>
  );
}

/** Desktop: the box in the top nav, results drop down under it. */
export function SearchBox() {
  const { history } = useShell();
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const boxRef = useRef(null);
  const res = useResults(q, history);
  useEffect(() => {
    const onDoc = (e) => !boxRef.current?.contains(e.target) && setOpen(false);
    const onKey = (e) => {
      if (e.key === '/' && !/input|textarea/i.test(document.activeElement?.tagName)) {
        e.preventDefault();
        boxRef.current?.querySelector('input')?.focus();
      }
    };
    document.addEventListener('pointerdown', onDoc);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onDoc);
      document.removeEventListener('keydown', onKey);
    };
  }, []);
  return (
    <div className="search" ref={boxRef}>
      <Icon name="search" size={19} className="search__icon" />
      <input
        className="search__input"
        placeholder="Search  /"
        aria-label="Search exercises, workouts and sessions"
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            setOpen(false);
            e.currentTarget.blur();
          }
          if (e.key === 'Enter') boxRef.current?.querySelector('.search__row')?.click();
        }}
      />
      {open && q.trim().length > 0 && (
        <div className="search__drop">
          <Results res={res} onPick={() => { setOpen(false); setQ(''); }} />
        </div>
      )}
    </div>
  );
}

/** Phones: the header's search button opens this. */
export function SearchSheet({ onClose }) {
  const { history } = useShell();
  const [q, setQ] = useState('');
  const res = useResults(q, history);
  return (
    <PanelSheet title="Search" onClose={onClose}>
      <input
        className="input"
        style={{ marginTop: 0 }}
        autoFocus
        placeholder="Exercise, workout or date…"
        value={q}
        onChange={(e) => setQ(e.target.value)}
      />
      <div style={{ marginTop: 8 }}>
        <Results res={res} onPick={onClose} />
      </div>
    </PanelSheet>
  );
}
