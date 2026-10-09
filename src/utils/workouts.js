// ── Saved workouts: your own and your trainer's ──────────────────
// Each one is account state in Firestore (state/workout-<id>), so the
// library, weekday schedule and daily add-ons follow the account to any
// device. Shape:
//   { id, name, kind: 'session' | 'addon', source: 'me' | 'trainer',
//     trainer, notes, adapt (session only: let the coach adapt it),
//     days: [0-6] (0 = Sunday; an add-on with no days runs every day),
//     exercises: [{ name, sets, reps, weight, rest, notes }],
//     createdAt, updatedAt }

import { cloudState, cloudStateKeys, cloudSetState } from '../db/cloud.js';
import { lastPerformance, suggestNextWeight } from './stats.js';
import { todayStr } from './helpers.js';

const PREFIX = 'workout-';
export const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** Display order: Monday first. */
export const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0];

export function listWorkouts() {
  return cloudStateKeys()
    .filter((k) => k.startsWith(PREFIX))
    .map((k) => cloudState(k))
    .filter((w) => w?.id)
    .sort((a, b) => (a.kind === b.kind ? (a.name || '').localeCompare(b.name || '') : a.kind === 'addon' ? 1 : -1));
}

export const getWorkout = (id) => (id ? cloudState(PREFIX + id, null) : null);

export function saveWorkout(w) {
  const id = w.id || `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  const now = Date.now();
  const clean = {
    id,
    name: (w.name || '').trim() || 'My workout',
    kind: w.kind === 'addon' ? 'addon' : 'session',
    source: w.source === 'trainer' ? 'trainer' : 'me',
    trainer: (w.trainer || '').trim(),
    notes: (w.notes || '').trim(),
    adapt: w.kind === 'addon' ? false : !!w.adapt,
    days: [...new Set((w.days || []).filter((d) => d >= 0 && d <= 6))].sort(),
    exercises: (w.exercises || [])
      .filter((e) => (e.name || '').trim())
      .map((e) => ({
        name: e.name.trim(),
        sets: Math.min(Math.max(parseInt(e.sets, 10) || 3, 1), 10),
        reps: String(e.reps || '').trim() || '10',
        weight: String(e.weight || '').trim(),
        rest: String(e.rest || '').trim(),
        notes: String(e.notes || '').trim(),
      })),
    createdAt: w.createdAt || now,
    updatedAt: now,
  };
  cloudSetState(PREFIX + id, clean);
  return clean;
}

export const deleteWorkout = (id) => cloudSetState(PREFIX + id, null);

export const blankExercise = () => ({ name: '', sets: 3, reps: '10', weight: '', rest: '', notes: '' });

const weekdayOf = (iso) => new Date(iso + 'T12:00:00').getDay();

/** What the library says to do on `date`: session workouts scheduled
 *  that weekday, and the add-ons that run that day. */
export function scheduledFor(date = todayStr(), all = listWorkouts()) {
  const wd = weekdayOf(date);
  return {
    sessions: all.filter((w) => w.kind === 'session' && w.days.includes(wd)),
    addOns: all.filter((w) => w.kind === 'addon' && (!w.days.length || w.days.includes(wd))),
  };
}

/** "Mon · Wed · Fri", "Every day", or "" (not scheduled). */
export function daysLabel(w) {
  if (!w.days.length) return w.kind === 'addon' ? 'Every day' : '';
  if (w.days.length === 7) return 'Every day';
  return WEEK_ORDER.filter((d) => w.days.includes(d)).map((d) => WEEKDAYS[d]).join(' · ');
}

/** A plan exercise from a saved one; the weight is the workout's own, or
 *  the next step from your logged history when it gives none. */
function planExercise(e, history, note) {
  const next = e.weight ? null : suggestNextWeight(lastPerformance(history, e.name), e.reps);
  const last = e.weight ? null : lastPerformance(history, e.name);
  const lastTop = last ? Math.max(0, ...last.sets.map((s) => parseFloat(s.weight) || 0)) : 0;
  const w = e.weight || (next ? `${next}kg` : lastTop ? `${lastTop}kg` : '');
  return {
    name: e.name,
    sets: e.sets,
    reps: e.reps,
    rpe: '',
    rest: e.rest || '90s',
    notes: [note, e.notes].filter(Boolean).join(' · '),
    alt: '',
    suggestedWeight: /^\d+(\.\d+)?$/.test(w) ? `${w}kg` : w,
    superset: '',
  };
}

const guessType = (w) => {
  const n = `${w.name} ${w.exercises.map((e) => e.name).join(' ')}`.toLowerCase();
  if (/stretch|mobility|yoga/.test(n)) return 'Stretch & Mobility';
  if (/run|cycle|bike|row|cardio|walk/.test(n) && !/press|squat|curl|deadlift/.test(n)) return 'Cardio';
  if (/core|abs|plank/.test(n) && !/press|squat|curl|deadlift|row/.test(n)) return 'Core';
  if (/push|chest/.test(n) && !/pull|leg/.test(n)) return 'Push';
  if (/pull|back/.test(n) && !/push|leg/.test(n)) return 'Pull';
  if (/leg|squat|lower/.test(n) && !/push|pull|upper/.test(n)) return 'Legs';
  return 'Full Body';
};

/** The plan a saved workout becomes without the AI (no key, offline, or
 *  the coach failed): exactly as written, weights from your history. */
export function templateToPlan(w, history) {
  const ex = w.exercises.map((e) => planExercise(e, history));
  return {
    sessionType: guessType(w),
    title: w.name,
    recoveryScore: null,
    reasoning: w.source === 'trainer' ? `${w.trainer || 'Your trainer'}'s workout, as written.` : 'Your saved workout, as written.',
    warmup: [],
    exercises: ex,
    cardio: null,
    cooldown: [],
    estTimeMin: Math.round(ex.reduce((a, e) => a + e.sets * 2.5, 0)) || 30,
    concerns: '',
    fromWorkout: { id: w.id, name: w.name, source: w.source, trainer: w.trainer, adapt: w.adapt },
  };
}

/** Keep-exact mode: the coach's plan may only add weights, cues and
 *  warnings — exercises, order, sets and reps are the workout's own. */
export function enforceExact(aiPlan, w, history) {
  const byName = new Map((aiPlan.exercises || []).map((e) => [e.name?.trim().toLowerCase(), e]));
  return {
    ...aiPlan,
    title: w.name,
    exercises: w.exercises.map((e, i) => {
      const base = planExercise(e, history);
      const ai = byName.get(e.name.toLowerCase()) || aiPlan.exercises?.[i] || {};
      return {
        ...base,
        rpe: ai.rpe || '',
        // the workout's own weight wins; otherwise the coach's suggestion
        suggestedWeight: e.weight ? base.suggestedWeight : ai.suggestedWeight || base.suggestedWeight,
        notes: [e.notes, ai.notes && ai.notes !== e.notes ? ai.notes : ''].filter(Boolean).join(' · '),
        alt: ai.alt || '',
      };
    }),
    fromWorkout: { id: w.id, name: w.name, source: w.source, trainer: w.trainer, adapt: false },
  };
}

/** Today's add-on routines go on the end of whatever the session is. */
export function appendAddOns(plan, addOns, history) {
  if (!addOns.length) return plan;
  const extra = addOns.flatMap((a) => a.exercises.map((e) => planExercise(e, history, `Add-on · ${a.name}`)));
  return {
    ...plan,
    exercises: [...(plan.exercises || []), ...extra],
    estTimeMin: (plan.estTimeMin || 0) + Math.round(extra.reduce((s, e) => s + e.sets * 2, 0)),
    addOns: addOns.map((a) => a.name),
  };
}

/** The saved workout as a brief for the coach's prompt. */
export function workoutBrief(w) {
  const who = w.source === 'trainer' ? `written by the athlete's trainer${w.trainer ? ` (${w.trainer})` : ''}` : 'saved by the athlete';
  const lines = w.exercises.map(
    (e, i) =>
      `${i + 1}. ${e.name} — ${e.sets} × ${e.reps}${e.weight ? ` @ ${e.weight}` : ''}${e.rest ? `, rest ${e.rest}` : ''}${e.notes ? ` (${e.notes})` : ''}`
  );
  return `"${w.name}", ${who}${w.notes ? ` — notes: ${w.notes}` : ''}:\n${lines.join('\n')}`;
}
