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

/**
 * Most recent performance of an exercise (by name, case-insensitive).
 * Returns { date, sets: [{weight, reps}] } or null.
 */
export function lastPerformance(history, exerciseName) {
  const key = (exerciseName || '').trim().toLowerCase();
  if (!key) return null;
  for (let i = history.length - 1; i >= 0; i--) {
    const s = history[i];
    const exI = (s.plan?.exercises || []).findIndex(
      (ex) => ex?.name?.trim().toLowerCase() === key
    );
    if (exI === -1) continue;
    const sets = (s.log?.[exI] || []).filter(setLogged);
    if (sets.length) {
      return { date: s.date, sets, repsRange: s.plan.exercises[exI].reps };
    }
  }
  return null;
}

/**
 * Simple progression hint: if every set last time hit the top of the
 * prescribed rep range, suggest +2.5kg on the heaviest set.
 */
export function suggestNextWeight(lastPerf, repsRange) {
  if (!lastPerf?.sets?.length) return null;
  const top = parseInt(String(repsRange || '').split(/[-–]/).pop(), 10);
  if (!top) return null;
  const weights = lastPerf.sets.map((s) => parseFloat(s.weight)).filter((n) => !Number.isNaN(n));
  if (!weights.length) return null;
  const allTopped = lastPerf.sets.every((s) => parseInt(s.reps, 10) >= top);
  if (!allTopped) return null;
  return Math.min(Math.max(...weights) + 2.5, 200);
}

/**
 * Deterministic progression targets for the AI prompt: for the most
 * trained exercises, last sets + whether the computed +2.5kg applies.
 */
export function progressionTargets(history, max = 10) {
  const out = [];
  for (const ex of exerciseSeries(history).slice(0, max)) {
    const lp = lastPerformance(history, ex.name);
    if (!lp) continue;
    const repsRange = lp.repsRange;
    const target = suggestNextWeight(lp, repsRange);
    const lastTxt = lp.sets.map((s) => `${s.weight || '?'}×${s.reps || '?'}`).join(' · ');
    out.push(
      `- ${ex.name}: last ${lastTxt}${target ? ` → ready for ${target}kg (all reps at top of range)` : ' → hold weight, push reps'}`
    );
  }
  return out.join('\n');
}

/** Pull HRV / resting-HR / steps numbers out of a free-form health string. */
export function parseHealthNumbers(text) {
  const t = String(text || '');
  const hrv = /hrv[^\d]{0,14}([\d.]+)/i.exec(t)?.[1];
  const rhr = /(?:rhr|resting[^\d]{0,12}(?:heart[^\d]{0,8})?(?:rate)?)[^\d]{0,14}([\d.]+)/i.exec(t)?.[1];
  const steps = /steps[^\d]{0,14}([\d,]+(?:\.\d+)?)/i.exec(t)?.[1];
  return {
    hrv: hrv ? parseFloat(hrv) : null,
    rhr: rhr ? parseFloat(rhr) : null,
    steps: steps ? Math.round(parseFloat(steps.replace(/,/g, ''))) : null,
  };
}

/**
 * 30-day HRV/RHR baselines (needs ≥3 samples). Prefers the health
 * store's daily rows; past check-in strings fill any gaps.
 */
export function healthBaseline(history, healthLog = [], days = 30) {
  const cutoff = Date.now() - days * DAY;
  const hrvs = [];
  const rhrs = [];
  const seen = new Set();
  for (const h of healthLog) {
    if (dateMs(h.date) < cutoff) continue;
    seen.add(h.date);
    if (h.hrv && h.hrv > 5 && h.hrv < 300) hrvs.push(h.hrv);
    if (h.rhr && h.rhr > 30 && h.rhr < 120) rhrs.push(h.rhr);
  }
  for (const s of history) {
    if (dateMs(s.date) < cutoff || seen.has(s.date)) continue;
    const { hrv, rhr } = parseHealthNumbers(s.checkin?.health);
    if (hrv && hrv > 5 && hrv < 300) hrvs.push(hrv);
    if (rhr && rhr > 30 && rhr < 120) rhrs.push(rhr);
  }
  const avg = (a) => a.reduce((x, y) => x + y, 0) / a.length;
  return {
    hrv: hrvs.length >= 3 ? Math.round(avg(hrvs)) : null,
    rhr: rhrs.length >= 3 ? Math.round(avg(rhrs)) : null,
  };
}

/** Text block of the last n days of Watch data, for the AI prompt. */
export function healthTrend(healthLog, n = 7) {
  const rows = (healthLog || []).slice(-n);
  if (rows.length < 2) return '';
  return rows
    .map((h) => {
      const bits = [];
      if (h.hrv) bits.push(`HRV ${h.hrv}ms`);
      if (h.rhr) bits.push(`RHR ${h.rhr}`);
      if (h.steps) bits.push(`${h.steps.toLocaleString()} steps`);
      return `${h.date}: ${bits.join(' · ') || h.raw || '—'}`;
    })
    .join('\n');
}

/**
 * Fatigue heuristic: volume AND average RPE rising across the last
 * 3 completed training weeks → suggest easing off. Returns a message
 * for the AI prompt, or null.
 */
export function fatigueSignal(history) {
  const weeks = weeklyBuckets(history, 4).slice(0, 3); // 3 full weeks before current
  if (!weeks.every((w) => w.count >= 2)) return null;
  const rpeOf = (start) => {
    const vals = history
      .filter((s) => mondayOf(s.date) === start && s.finished && s.fin?.rpe != null)
      .map((s) => Number(s.fin.rpe))
      .filter((n) => !Number.isNaN(n));
    return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
  };
  const rpes = weeks.map((w) => rpeOf(w.start));
  if (rpes.some((r) => r === null)) return null;
  const volUp = weeks[0].volume < weeks[1].volume && weeks[1].volume < weeks[2].volume;
  const rpeUp = rpes[0] < rpes[1] && rpes[1] < rpes[2];
  if (volUp && rpeUp) {
    return `Training volume and average session RPE have both risen for 3 consecutive weeks (volume ${weeks.map((w) => w.volume).join('→')}kg, RPE ${rpes.map((r) => r.toFixed(1)).join('→')}). Fatigue may be accumulating — consider a lighter session or deload if today's readiness is not clearly good.`;
  }
  return null;
}

/**
 * Gentle nudge for the "make it harder" flow: compares today's
 * check-in (sleep, soreness) and Watch data (HRV/RHR vs 30-day
 * baseline) plus the fatigue trend. Returns one soft sentence, or
 * null when recovery looks fine — it never blocks, only reminds.
 */
export function recoveryCaution(checkin, history, healthLog = []) {
  const bits = [];
  if (/poor/i.test(checkin?.sleep || '')) bits.push('sleep was poor last night');
  const today = parseHealthNumbers(checkin?.health);
  const base = healthBaseline(history, healthLog);
  if (today.hrv && base.hrv) {
    const d = Math.round(((today.hrv - base.hrv) / base.hrv) * 100);
    if (d <= -10) bits.push(`HRV is ${Math.abs(d)}% below your 30-day normal`);
  }
  if (today.rhr && base.rhr) {
    const d = Math.round(((today.rhr - base.rhr) / base.rhr) * 100);
    if (d >= 7) bits.push('resting heart rate is running a bit high');
  }
  if (/very sore/i.test(checkin?.soreness || '')) bits.push("you're still quite sore");
  if (fatigueSignal(history)) bits.push('volume and effort have been climbing for a few weeks');
  if (!bits.length) return null;
  const list =
    bits.length > 1
      ? bits.slice(0, -1).join(', ') + ' and ' + bits[bits.length - 1]
      : bits[0];
  return `Heads-up: ${list}. Extra work is your call — maybe keep a rep or two in the tank.`;
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
