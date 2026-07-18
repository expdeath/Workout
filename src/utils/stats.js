// ── Training statistics ──────────────────────────────────────────
// Pure helpers over session history. Used by the Progress screen,
// the Home streak/weekly-review cards, and the AI weekly review.

const DAY = 86400000;

const dateMs = (iso) => new Date(iso + 'T12:00:00').getTime();

import { setLogged, fmtSet } from './helpers.js';

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

function bestSetE1RM(session, exIndex) {
  let best = null;
  for (const s of session.log?.[exIndex] || []) {
    if (!setLogged(s)) continue;
    const e = epley1RM(s.weight, s.reps);
    if (e && (best === null || e > best)) best = e;
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
 * Per-exercise series across all history: best set weight and best
 * estimated 1RM per session.
 * Returns [{ name, points: [{date, w, e}] }], most-trained first.
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
      map.get(key).points.push({ date: s.date, w, e: bestSetE1RM(s, i) });
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
 * prescribed rep range, suggest +2.5kg on the heaviest set. Per-set
 * effort taps refine it: any grind → hold the weight (reps hit, but
 * barely); every set rated easy → jump +5kg instead.
 */
export function suggestNextWeight(lastPerf, repsRange) {
  if (!lastPerf?.sets?.length) return null;
  const top = parseInt(String(repsRange || '').split(/[-–]/).pop(), 10);
  if (!top) return null;
  const weights = lastPerf.sets.map((s) => parseFloat(s.weight)).filter((n) => !Number.isNaN(n));
  if (!weights.length) return null;
  const allTopped = lastPerf.sets.every((s) => parseInt(s.reps, 10) >= top);
  if (!allTopped) return null;
  const efforts = lastPerf.sets.map((s) => s.effort).filter(Boolean);
  if (efforts.includes('grind')) return null;
  const jump =
    efforts.length === lastPerf.sets.length && efforts.every((e) => e === 'easy') ? 5 : 2.5;
  return Math.min(Math.max(...weights) + jump, 200);
}

/** Epley estimated 1RM, smoothed so 1 rep returns the weight itself. */
export function epley1RM(weight, reps) {
  const w = parseFloat(weight);
  const r = parseInt(reps, 10);
  if (Number.isNaN(w) || Number.isNaN(r) || w <= 0 || r <= 0) return null;
  return Math.round(w * (1 + (r - 1) / 30) * 10) / 10;
}

/**
 * All-time records per exercise: heaviest set and best estimated 1RM.
 * Returns [{ name, count, weight: {w, reps, date}, e1rm: {v, date} }],
 * most-trained first.
 */
export function prRecords(history) {
  const map = new Map();
  for (const s of history) {
    (s.plan?.exercises || []).forEach((ex, i) => {
      if (!ex?.name) return;
      const key = ex.name.trim().toLowerCase();
      for (const set of s.log?.[i] || []) {
        if (!setLogged(set)) continue;
        const w = parseFloat(set.weight);
        if (Number.isNaN(w) || w <= 0) continue;
        if (!map.has(key)) {
          map.set(key, { name: ex.name.trim(), count: 0, weight: null, e1rm: null });
        }
        const rec = map.get(key);
        rec.count++;
        if (!rec.weight || w > rec.weight.w) rec.weight = { w, reps: set.reps, date: s.date };
        const e = epley1RM(w, set.reps);
        if (e && (!rec.e1rm || e > rec.e1rm.v)) rec.e1rm = { v: e, date: s.date };
      }
    });
  }
  return [...map.values()].sort((a, b) => b.count - a.count);
}

/**
 * New records set by `session` vs `prior` history (which must not
 * contain the session). First-time exercises don't count — a PR needs
 * a previous best to beat. Heaviest-set PRs win over e1RM (rep) PRs.
 */
export function detectPRs(session, prior) {
  const before = new Map(prRecords(prior).map((r) => [r.name.toLowerCase(), r]));
  const out = [];
  for (const rec of prRecords([session])) {
    const old = before.get(rec.name.toLowerCase());
    if (!old) continue;
    if (rec.weight && old.weight && rec.weight.w > old.weight.w) {
      out.push({ name: rec.name, kind: 'weight', from: old.weight.w, to: rec.weight.w });
    } else if (rec.e1rm && old.e1rm && rec.e1rm.v > old.e1rm.v) {
      out.push({ name: rec.name, kind: 'e1rm', from: old.e1rm.v, to: rec.e1rm.v });
    }
  }
  return out;
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
    const lastTxt = lp.sets
      .map((s) => `${fmtSet(s)}${s.effort ? `(${s.effort})` : ''}`)
      .join(' · ');
    out.push(
      `- ${ex.name}: last ${lastTxt}${target ? ` → ready for ${target}kg (all reps at top of range)` : ' → hold weight, push reps'}`
    );
  }
  return out.join('\n');
}

/** Pull HRV / resting-HR / steps / sleep / VO₂max / energy / SpO₂ …
 *  numbers out of a free-form health string (Watch shortcut payload). */
export function parseHealthNumbers(text) {
  const t = String(text || '');
  const num = (re, clamp = null) => {
    const m = re.exec(t)?.[1];
    if (!m) return null;
    const n = parseFloat(m.replace(/,/g, ''));
    if (Number.isNaN(n)) return null;
    return clamp && !(n >= clamp[0] && n <= clamp[1]) ? null : n;
  };
  const hrv = /hrv[^\d]{0,14}([\d.]+)/i.exec(t)?.[1];
  const rhr = /(?:rhr|resting[^\d]{0,12}(?:heart[^\d]{0,8})?(?:rate)?)[^\d]{0,14}([\d.]+)/i.exec(t)?.[1];
  const steps = /\bsteps[^\d]{0,14}([\d,]+(?:\.\d+)?)/i.exec(t)?.[1];
  let sleepH = null;
  // Shortcut label first: "SleepHrs: <duration sum>" — the Watch sums
  // sample durations whose unit varies by iOS (seconds/minutes/hours)
  // digits must follow the label directly — an empty value would
  // otherwise swallow the next metric's number
  const slLabel = /sleep\s*hrs?:?\s*([\d.]+)/i.exec(t);
  if (slLabel) {
    const n = parseFloat(slLabel[1]);
    if (n > 1200) sleepH = n / 3600; // seconds
    else if (n > 20) sleepH = n / 60; // minutes
    else sleepH = n; // hours
    sleepH = sleepH > 0 && sleepH < 20 ? Math.round(sleepH * 10) / 10 : null;
  }
  // free-form fallbacks: "Sleep 7h 20m" · "slept 6.5 hours" · "sleep: 7:20"
  if (sleepH === null) {
    const sl =
      /sle(?:ep|pt)[^\d]{0,14}(\d{1,2})(?::(\d{2})|\s*h(?:ours?|rs?)?(?:\s*(\d{1,2})\s*m)?|(\.\d+))?/i.exec(t);
    if (sl) {
      sleepH = parseInt(sl[1], 10);
      if (sl[2]) sleepH += parseInt(sl[2], 10) / 60; // 7:20
      else if (sl[3]) sleepH += parseInt(sl[3], 10) / 60; // 7h 20m
      else if (sl[4]) sleepH += parseFloat(sl[4]); // 6.5
      sleepH = sleepH > 0 && sleepH < 20 ? Math.round(sleepH * 10) / 10 : null;
    }
  }
  return {
    hrv: hrv ? parseFloat(hrv) : null,
    rhr: rhr ? parseFloat(rhr) : null,
    steps: steps ? Math.round(parseFloat(steps.replace(/,/g, ''))) : null,
    sleepH,
    vo2max: num(/vo2\s*max[^\d]{0,14}([\d.]+)/i, [10, 90]),
    kcal: num(/(?:active\s*kcal|active\s*energy)[^\d]{0,14}([\d,]+(?:\.\d+)?)/i, [1, 8000]),
    exerciseMin: num(/exercise\s*min[^\d]{0,14}([\d,]+(?:\.\d+)?)/i, [1, 1000]),
    distKm: num(/distance\s*km[^\d]{0,14}([\d.]+)/i, [0.1, 200]),
    // HealthKit reports oxygen saturation as a 0–1 fraction; Shortcuts
    // may render either "0.96" or "96%"
    spo2: (() => {
      const n = num(/spo2[^\d]{0,14}([\d.]+)/i);
      if (n === null) return null;
      const pct = n <= 1 ? Math.round(n * 1000) / 10 : n;
      return pct >= 70 && pct <= 100 ? pct : null;
    })(),
    respRate: num(/resp\s*rate[^\d]{0,14}([\d.]+)/i, [5, 40]),
    wristC: num(/wrist\s*temp[^\d]{0,14}([\d.]+)/i, [20, 45]),
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
      if (h.sleepH) bits.push(`sleep ${h.sleepH}h`);
      if (h.weightKg) bits.push(`bodyweight ${h.weightKg}kg`);
      if (h.steps) bits.push(`${h.steps.toLocaleString()} steps`);
      if (h.vo2max) bits.push(`VO2max ${h.vo2max}`);
      if (h.kcal) bits.push(`${Math.round(h.kcal)}kcal active`);
      if (h.exerciseMin) bits.push(`${Math.round(h.exerciseMin)}min exercise`);
      if (h.distKm) bits.push(`${h.distKm}km`);
      if (h.spo2) bits.push(`SpO2 ${h.spo2}%`);
      if (h.respRate) bits.push(`RR ${h.respRate}/min`);
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
 * Lifts that have stopped progressing: trained ≥3 times in the last
 * `days`, and the best weight of the latest exposure is no better
 * than either of the two before it. Returns [{ name, weight }].
 */
export function stalledProgressions(history, days = 35) {
  const cutoff = Date.now() - days * DAY;
  const out = [];
  for (const ex of exerciseSeries(history)) {
    const recent = ex.points.filter((p) => dateMs(p.date) >= cutoff);
    if (recent.length < 3) continue;
    const [a, b, c] = recent.slice(-3).map((p) => p.w);
    if (c <= a && c <= b) out.push({ name: ex.name, weight: c });
  }
  return out;
}

/**
 * Deload heuristic: rising fatigue (volume + RPE climbing, from
 * fatigueSignal) OR ≥2 stalled lifts during consistent training.
 * Returns { reason } for the Home card and the AI prompt, or null.
 */
export function deloadSignal(history) {
  const fatigue = fatigueSignal(history);
  const stalled = stalledProgressions(history);
  const weeks = weeklyBuckets(history, 4).slice(0, 3);
  const consistent = weeks.every((w) => w.count >= 3);
  if (fatigue) {
    return {
      reason:
        'Volume and session effort have both climbed for 3 straight weeks. A lighter week now (−30-40% volume, nothing near failure) usually buys the next PR.',
    };
  }
  if (consistent && stalled.length >= 2) {
    return {
      reason: `${stalled
        .slice(0, 3)
        .map((s) => s.name)
        .join(', ')} ${stalled.length > 1 ? 'have' : 'has'} stopped progressing despite consistent training — a classic sign accumulated fatigue is masking fitness. Consider a deload week (−30-40% volume, no failure), then rebuild.`,
    };
  }
  return null;
}

// ── Muscle-group tagging ─────────────────────────────────────────
// Keyword classifier — order matters (e.g. "leg raise" is core, and
// "leg press" must hit Legs before the generic "press" hits Chest).
const MUSCLE_RULES = [
  ['Cardio', /bike|cycling|treadmill|stair|elliptical|jump rope|sprint|incline walk|\berg\b|swim|\brun(?:ning)?\b|\bjogg?(?:ing)?\b|\brower\b|row(?:ing)?\s*machine|cross[- ]?trainer|air ?dyne|assault ?bike|brisk walk|walking pad|\bhike\b|hiking|\bruck(?:ing)?\b|\bcardio\b/i],
  ['Core', /plank|crunch|\babs?\b|core|russian|leg raise|knee raise|dead bug|pallof|rollout|woodchop/i],
  ['Legs', /squat|\bleg\b|lunge|calf|hamstring|quad|glute|hip thrust|\brdl\b|romanian|adductor|abductor|step[- ]?up|nordic/i],
  ['Back', /\brows?\b|rowing|pulldown|pull[- ]?down|pull[- ]?up|chin[- ]?up|\blats?\b|deadlift|shrug|back extension|face pull|hyperextension/i],
  ['Shoulders', /shoulder|overhead|\bohp\b|lateral raise|side raise|rear delt|delt|arnold|military|upright/i],
  ['Chest', /bench|chest|\bpecs?\b|\bfly\b|flye|dips?\b|push[- ]?up|crossover/i],
  ['Arms', /curl|tricep|bicep|pushdown|push[- ]?down|extension|skull|hammer|preacher|kickback|forearm|wrist/i],
];

/** Best-effort muscle group for an exercise name. */
export function muscleGroupOf(name) {
  const n = String(name || '');
  for (const [group, re] of MUSCLE_RULES) if (re.test(n)) return group;
  return 'Other';
}

/** Cardio exercises log time/distance instead of weight×reps. */
export const isCardio = (name) => muscleGroupOf(name) === 'Cardio';

/**
 * Training balance over the last `days`: per muscle group, sets +
 * volume + days since last trained. Sorted by sets, busiest first.
 * Returns [{ group, sets, volume, lastDaysAgo }].
 */
export function muscleBalance(history, days = 14) {
  const cutoff = Date.now() - days * DAY;
  const map = new Map();
  for (const s of history) {
    (s.plan?.exercises || []).forEach((ex, i) => {
      const done = (s.log?.[i] || []).filter(setLogged);
      if (!done.length) return;
      const group = muscleGroupOf(ex?.name);
      if (group === 'Other' || group === 'Cardio') return;
      if (!map.has(group)) map.set(group, { group, sets: 0, volume: 0, last: null });
      const g = map.get(group);
      const ms = dateMs(s.date);
      if (g.last === null || ms > g.last) g.last = ms;
      if (ms < cutoff) return;
      g.sets += done.length;
      for (const set of done) {
        const w = parseFloat(set.weight);
        const r = parseFloat(set.reps);
        if (!Number.isNaN(w) && !Number.isNaN(r)) g.volume += w * r;
      }
    });
  }
  return [...map.values()]
    .map((g) => ({
      group: g.group,
      sets: g.sets,
      volume: Math.round(g.volume),
      lastDaysAgo: g.last === null ? null : Math.max(0, Math.round((Date.now() - g.last) / DAY)),
    }))
    .sort((a, b) => b.sets - a.sets);
}

/** One-line balance summary for the AI prompt, or ''. */
export function muscleGapNote(history) {
  const bal = muscleBalance(history);
  if (!bal.length) return '';
  const line = bal
    .map((g) => `${g.group} ${g.sets} sets${g.lastDaysAgo >= 7 ? ` (last ${g.lastDaysAgo}d ago)` : ''}`)
    .join(', ');
  const gaps = bal.filter((g) => g.lastDaysAgo >= 10).map((g) => g.group);
  return (
    `Muscle balance last 14 days: ${line}.` +
    (gaps.length ? ` NOT TRAINED IN 10+ DAYS: ${gaps.join(', ')} — bias today's selection toward the gap if recovery allows.` : '')
  );
}

// ── Goals ────────────────────────────────────────────────────────
/**
 * Parse free-text goals (one per line) and measure progress.
 * "Bench Press 80kg" matches an exercise's all-time best set weight;
 * "4 sessions a week" matches weekly frequency; anything else is
 * kept as a plain line. Returns [{ text, current, target, unit }].
 */
export function goalProgress(history, goalsText) {
  const lines = String(goalsText || '')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);
  if (!lines.length) return [];
  const records = prRecords(history);
  const { thisWeek } = weekStats(history);
  return lines.map((text) => {
    const freq = /(\d+)\s*(?:x|sessions?|days?)\s*(?:a|per|\/)\s*week/i.exec(text);
    if (freq) {
      return { text, current: thisWeek, target: parseInt(freq[1], 10), unit: ' this week' };
    }
    const kg = /^(.*?)\s+(\d+(?:\.\d+)?)\s*kg\b/i.exec(text);
    if (kg) {
      const namePart = kg[1].trim().toLowerCase();
      const rec = records.find(
        (r) =>
          r.weight &&
          (r.name.toLowerCase().includes(namePart) || namePart.includes(r.name.toLowerCase()))
      );
      if (rec) {
        return { text, current: rec.weight.w, target: parseFloat(kg[2]), unit: 'kg' };
      }
    }
    return { text, current: null, target: null, unit: '' };
  });
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
  if (today.sleepH && today.sleepH < 6 && !bits.length) {
    bits.push(`you only slept ${today.sleepH}h`);
  }
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
