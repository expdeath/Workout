// ── Training statistics ──────────────────────────────────────────
// Pure helpers over session history. Used by the Progress screen,
// the Home streak/weekly-review cards, and the AI weekly review.

const DAY = 86400000;

const dateMs = (iso) => new Date(iso + 'T12:00:00').getTime();

import { setLogged } from './helpers.js';

/** Monday (ISO date string) of the week containing the given date. */
export function mondayOf(iso) {
  const d = new Date(iso + 'T12:00:00');
  const shift = (d.getDay() + 6) % 7; // Mon=0 … Sun=6
  return new Date(d.getTime() - shift * DAY).toISOString().slice(0, 10);
}

function bestSetWeight(session, exIndex) {
  let best = null;
  for (const s of session.log?.[exIndex] || []) {
    if (!setLogged(s)) continue;
    const w = parseFloat(s.weight);
    if (!Number.isNaN(w) && (best === null || w > best)) best = w;
  }
  return best;
}

/** Total volume (Σ weight×reps of done sets) for one session, in kg. */
export function sessionVolume(session) {
  let vol = 0;
  for (const ex of session.log || []) {
    for (const s of ex) {
      if (!setLogged(s)) continue;
      const w = parseFloat(s.weight);
      const r = parseFloat(s.reps);
      if (!Number.isNaN(w) && !Number.isNaN(r)) vol += w * r;
    }
  }
  return Math.round(vol);
}

/**
 * Per-exercise weight series across all history.
 * Returns [{ name, points: [{date, w}] }], most-trained first.
 */
export function exerciseSeries(history) {
  const map = new Map();
  for (const s of history) {
    (s.plan?.exercises || []).forEach((ex, i) => {
      if (!ex?.name) return;
      const w = bestSetWeight(s, i);
      if (w === null) return;
      const key = ex.name.trim().toLowerCase();
      if (!map.has(key)) map.set(key, { name: ex.name.trim(), points: [] });
      map.get(key).points.push({ date: s.date, w });
    });
  }
  return [...map.values()].sort((a, b) => b.points.length - a.points.length);
}

/**
 * Weekly buckets for the last n weeks (oldest → newest, current week last).
 * Returns [{ start, count, volume }].
 */
export function weeklyBuckets(history, n = 8) {
  const thisMonday = mondayOf(new Date().toISOString().slice(0, 10));
  const buckets = [];
  for (let i = n - 1; i >= 0; i--) {
    const start = new Date(dateMs(thisMonday) - i * 7 * DAY)
      .toISOString()
      .slice(0, 10);
    buckets.push({ start, count: 0, volume: 0 });
  }
  const index = new Map(buckets.map((b, i) => [b.start, i]));
  for (const s of history) {
    const i = index.get(mondayOf(s.date));
    if (i === undefined) continue;
    buckets[i].count++;
    buckets[i].volume += sessionVolume(s);
  }
  return buckets;
}

/**
 * Lifts whose best weight in the last `days` beats their best before.
 * Returns [{ name, from, to }].
 */
export function progressions(history, days = 7) {
  const cutoff = Date.now() - days * DAY;
  const out = [];
  for (const ex of exerciseSeries(history)) {
    const recent = ex.points.filter((p) => dateMs(p.date) >= cutoff);
    const before = ex.points.filter((p) => dateMs(p.date) < cutoff);
    if (!recent.length || !before.length) continue;
    const to = Math.max(...recent.map((p) => p.w));
    const from = Math.max(...before.map((p) => p.w));
    if (to > from) out.push({ name: ex.name, from, to });
  }
  return out.sort((a, b) => b.to - b.from - (a.to - a.from)).slice(0, 5);
}

/**
 * Streak stats: sessions this week + consecutive weeks with ≥3 sessions.
 * The current week extends the streak once it reaches 3.
 */
export function weekStats(history, target = 3) {
  const counts = new Map();
  for (const s of history) {
    const wk = mondayOf(s.date);
    counts.set(wk, (counts.get(wk) || 0) + 1);
  }
  const thisMonday = mondayOf(new Date().toISOString().slice(0, 10));
  const thisWeek = counts.get(thisMonday) || 0;
  let streak = thisWeek >= target ? 1 : 0;
  for (let i = 1; ; i++) {
    const wk = new Date(dateMs(thisMonday) - i * 7 * DAY)
      .toISOString()
      .slice(0, 10);
    if ((counts.get(wk) || 0) >= target) streak++;
    else break;
  }
  return { thisWeek, streak };
}

/** Compact text summary of the last 7 days, for the AI weekly review. */
export function lastWeekSummary(history) {
  const cutoff = Date.now() - 7 * DAY;
  const recent = history.filter((s) => dateMs(s.date) >= cutoff);
  if (!recent.length) return null;
  const lines = recent.map((s) => {
    const vol = sessionVolume(s);
    return `${s.date} ${s.plan?.sessionType}${s.finished ? '' : ' (not finished)'} — RPE ${s.fin?.rpe ?? '?'}${s.fin?.pain ? ', pain: ' + s.fin.pain : ''}${vol ? `, volume ${vol}kg` : ''}`;
  });
  const ups = progressions(history, 7).map(
    (p) => `${p.name} ${p.from}→${p.to}kg`
  );
  return {
    count: recent.length,
    lines: lines.join('\n'),
    progressions: ups.join(', ') || 'none',
  };
}
