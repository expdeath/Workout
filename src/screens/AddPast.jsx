import React, { useMemo, useState } from 'react';
import Seg from '../components/Seg';
import {
  todayStr,
  daysAgoStr,
  fmtDate,
  setLogged,
  cleanWeight,
  cleanReps,
  cleanTime,
  cleanDist,
} from '../utils/helpers';
import { logMode } from '../utils/stats';

// Log a workout after the fact — forgot to log it, or trained without
// the app. No check-in, no AI: pick the day, the type, and type in what
// you did. Saved as a finished session on that date, so stats, records,
// and tomorrow's plan all see it.
const TYPES = ['Push', 'Pull', 'Legs', 'Full Body', 'Core', 'Cardio', 'Stretch & Mobility'];

const emptySet = () => ({ weight: '', reps: '', time: '', dist: '', done: false });
const emptyExercise = () => ({ name: '', sets: [emptySet(), emptySet(), emptySet()] });

export default function AddPast({ history, onCancel, onSave }) {
  const [date, setDate] = useState(daysAgoStr(1));
  const [sessionType, setSessionType] = useState('Full Body');
  const [exercises, setExercises] = useState([emptyExercise()]);
  const [durationMin, setDurationMin] = useState('');
  const [rpe, setRpe] = useState(7);
  const [feedback, setFeedback] = useState('');
  const [error, setError] = useState('');

  // exercise names you've logged before, most recent first — typing
  // "ben…" offers "Bench press" so names match and progressions line up
  const knownNames = useMemo(() => {
    const seen = new Map();
    for (const s of [...history].reverse()) {
      for (const ex of s.plan?.exercises || []) {
        const n = ex?.name?.trim();
        if (n && !seen.has(n.toLowerCase())) seen.set(n.toLowerCase(), n);
      }
    }
    return [...seen.values()].slice(0, 200);
  }, [history]);

  // most recent session of this type up to the chosen day — one tap
  // copies its exercises and sets as a starting point
  const lastOfType = useMemo(
    () =>
      [...history]
        .reverse()
        .find((s) => s.plan?.sessionType === sessionType && s.date <= date && s.plan.exercises?.length),
    [history, sessionType, date]
  );

  const copyFrom = (s) => {
    setExercises(
      s.plan.exercises.map((ex, i) => {
        const sets = (s.log?.[i] || []).filter(setLogged).map((x) => ({ ...emptySet(), ...x }));
        return { name: ex.name, sets: sets.length ? sets : [emptySet()] };
      })
    );
    setError('');
  };

  const patchEx = (exI, patch) =>
    setExercises((xs) => xs.map((ex, i) => (i === exI ? { ...ex, ...patch } : ex)));

  const patchSet = (exI, setI, field, val) => {
    if (field === 'weight') val = cleanWeight(val);
    if (field === 'reps') val = cleanReps(val);
    if (field === 'time') val = cleanTime(val);
    if (field === 'dist') val = cleanDist(val);
    setExercises((xs) =>
      xs.map((ex, i) =>
        i === exI
          ? { ...ex, sets: ex.sets.map((s, j) => (j === setI ? { ...s, [field]: val } : s)) }
          : ex
      )
    );
  };

  const save = () => {
    if (!date || date > todayStr()) {
      setError('Pick a day on or before today.');
      return;
    }
    const plan = [];
    const log = [];
    for (const ex of exercises) {
      const name = ex.name.trim().slice(0, 60);
      if (!name) continue;
      const mode = logMode(name, sessionType);
      // keep only the fields this kind of exercise logs, and only sets
      // that actually happened
      const sets = ex.sets
        .map((s) =>
          mode === 'cardio'
            ? { time: s.time, dist: s.dist, done: !!(s.time || s.dist) }
            : mode === 'check'
            ? { done: !!s.done }
            : { weight: s.weight, reps: s.reps, done: !!(s.weight || s.reps) }
        )
        .filter((s) => s.done);
      if (!sets.length) continue;
      const reps = sets.map((s) => parseInt(s.reps, 10)).filter((n) => n > 0);
      const lo = Math.min(...reps);
      const hi = Math.max(...reps);
      plan.push({
        name,
        sets: sets.length,
        reps: reps.length ? (lo === hi ? String(lo) : `${lo}-${hi}`) : '',
        rest: '',
        rpe: '',
      });
      log.push(sets);
    }
    if (!plan.length) {
      setError('Add at least one exercise with a logged set.');
      return;
    }
    onSave({
      date,
      sessionType,
      exercises: plan,
      log,
      durationMin: Math.round(Number(durationMin)) || undefined,
      rpe,
      feedback: feedback.trim(),
    });
  };

  const preset = ['1', '2', '3'].find((n) => daysAgoStr(Number(n)) === date) || '';

  return (
    <div className="screen screen--slide-in">
      <header className="header">
        <button className="ghost-btn" onClick={onCancel}>Cancel</button>
        <div className="brand-sm">PAST WORKOUT</div>
        <div />
      </header>

      <p className="subtitle" style={{ marginTop: 0 }}>
        Missed logging a session? Add it here — it counts toward your stats,
        records, and the coach's next plan.
      </p>

      <div className="q-label q-label--row">
        <span>Day</span>
        <span className="q-label__value">{date ? fmtDate(date) : '—'}</span>
      </div>
      <Seg
        options={[
          ['1', 'Yesterday'],
          ['2', '2 days ago'],
          ['3', '3 days ago'],
        ]}
        value={preset}
        onChange={(n) => setDate(daysAgoStr(Number(n)))}
      />
      <input
        type="date"
        className="input"
        max={todayStr()}
        value={date}
        onChange={(e) => setDate(e.target.value)}
      />

      <div className="q-label">Session type</div>
      <div className="seg-group seg-group--wrap">
        {TYPES.map((t) => (
          <button
            key={t}
            className={'seg-btn' + (sessionType === t ? ' seg-on' : '')}
            onClick={() => setSessionType(t)}
          >
            {t}
          </button>
        ))}
      </div>

      <div className="q-label q-label--row">
        <span>Exercises</span>
        {lastOfType && (
          <button className="link-btn" style={{ padding: 0 }} onClick={() => copyFrom(lastOfType)}>
            ↺ Copy last {sessionType} ({fmtDate(lastOfType.date)})
          </button>
        )}
      </div>

      <datalist id="past-exercise-names">
        {knownNames.map((n) => (
          <option key={n} value={n} />
        ))}
      </datalist>

      {exercises.map((ex, exI) => {
        const mode = logMode(ex.name, sessionType);
        return (
          <div key={exI} className="ex-card">
            <input
              className="input"
              style={{ marginTop: 0 }}
              list="past-exercise-names"
              placeholder="Exercise — e.g. Bench press, Running"
              value={ex.name}
              onChange={(e) => patchEx(exI, { name: e.target.value })}
            />
            {ex.sets.map((s, setI) => (
              <div key={setI} className="set-row">
                <span className="mono set-x" style={{ width: 20 }}>{setI + 1}</span>
                {mode === 'check' ? (
                  <button
                    className={'set-chk' + (s.done ? ' set-chk-on' : '')}
                    aria-label={s.done ? 'Mark not done' : 'Mark done'}
                    onClick={() => patchSet(exI, setI, 'done', !s.done)}
                  >
                    {s.done ? '✓' : ''}
                  </button>
                ) : mode === 'cardio' ? (
                  <>
                    <input
                      className="set-input"
                      inputMode="decimal"
                      placeholder="min"
                      value={s.time || ''}
                      onChange={(e) => patchSet(exI, setI, 'time', e.target.value)}
                    />
                    <span className="set-x">min</span>
                    <input
                      className="set-input"
                      inputMode="decimal"
                      placeholder="km"
                      value={s.dist || ''}
                      onChange={(e) => patchSet(exI, setI, 'dist', e.target.value)}
                    />
                    <span className="set-x">km</span>
                  </>
                ) : (
                  <>
                    <input
                      className="set-input"
                      inputMode="decimal"
                      placeholder="kg"
                      value={s.weight || ''}
                      onChange={(e) => patchSet(exI, setI, 'weight', e.target.value)}
                    />
                    <span className="set-x">×</span>
                    <input
                      className="set-input"
                      inputMode="numeric"
                      placeholder="reps"
                      value={s.reps || ''}
                      onChange={(e) => patchSet(exI, setI, 'reps', e.target.value)}
                    />
                  </>
                )}
              </div>
            ))}
            <div className="links-row" style={{ justifyContent: 'flex-start', marginTop: 8 }}>
              <button
                className="link-btn"
                onClick={() => patchEx(exI, { sets: [...ex.sets, emptySet()] })}
              >
                + set
              </button>
              {ex.sets.length > 1 && (
                <>
                  <span className="links-row__dot">·</span>
                  <button
                    className="link-btn"
                    onClick={() => patchEx(exI, { sets: ex.sets.slice(0, -1) })}
                  >
                    − set
                  </button>
                </>
              )}
              {exercises.length > 1 && (
                <>
                  <span className="links-row__dot">·</span>
                  <button
                    className="link-btn"
                    onClick={() => setExercises((xs) => xs.filter((_, i) => i !== exI))}
                  >
                    ✕ remove
                  </button>
                </>
              )}
            </div>
          </div>
        );
      })}

      <button
        className="more-toggle"
        onClick={() => setExercises((xs) => [...xs, emptyExercise()])}
      >
        <span>+ Add exercise</span>
      </button>

      <div className="q-label">Duration (optional)</div>
      <div className="set-row" style={{ marginTop: 0 }}>
        <input
          className="set-input"
          inputMode="decimal"
          placeholder="min"
          value={durationMin}
          onChange={(e) => setDurationMin(cleanTime(e.target.value))}
        />
        <span className="set-x">min</span>
      </div>

      <div className="q-label q-label--row">
        <span>Session effort</span>
        <span className="q-label__value">{rpe}/10</span>
      </div>
      <input
        type="range"
        className="slider"
        min="1"
        max="10"
        step="1"
        value={rpe}
        onChange={(e) => setRpe(Number(e.target.value))}
      />
      <input
        className="input"
        placeholder="Notes (optional)"
        value={feedback}
        onChange={(e) => setFeedback(e.target.value)}
      />

      {error && <div className="err-box">{error}</div>}

      <button className="big-btn" onClick={save}>
        Save to {date ? fmtDate(date) : 'log'}
      </button>
      <div style={{ height: 24 }} />
    </div>
  );
}
