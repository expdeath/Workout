// Derived numbers for the dashboard-style screens (Today, Log, Progress,
// Records) and the notification feed. The iOS app's Stats/Dashboard.swift
// mirrors this file, so both apps show the same figures from the same data.
import {
  weekStats,
  healthBaseline,
  deloadSignal,
  sessionVolume,
  detectPRs,
  prRecords,
  goalProgress,
  logMode,
  lastPerformance,
  suggestNextWeight,
  mondayOf,
} from './stats.js';
import { daysAgoStr, todayStr, fmtDate } from './helpers.js';
import { estimateSessionCalories } from './calories.js';

// ── Readiness pill ──

/** RESTED / STEADY / FATIGUED from the latest Watch day (≤ 2 days old)
 *  against the 30-day baseline, plus the training-load deload signal.
 *  null when there's no recent health data and no load warning.
 *  → { label, tone: 'good'|'ok'|'low', note } */
export function readiness(history, health) {
  const deload = deloadSignal(history);
  const cutoff = daysAgoStr(2);
  const h = [...health].filter((r) => r.date >= cutoff).sort((a, b) => (a.date < b.date ? 1 : -1))[0];
  if (!h) return deload ? { label: 'Deload', tone: 'low', note: deload.reason } : null;
  const base = healthBaseline(history, health);
  let low = 0;
  let good = 0;
  const bits = [];
  if (h.hrv && base.hrv) {
    const d = Math.round(h.hrv - base.hrv);
    bits.push(`HRV ${Math.round(h.hrv)} ms (${d >= 0 ? '+' : ''}${d} vs your average)`);
    if (h.hrv < base.hrv * 0.85) low++;
    else if (h.hrv >= base.hrv * 0.95) good++;
  }
  if (h.rhr && base.rhr) {
    if (h.rhr > base.rhr + 5) {
      low++;
      bits.push(`resting HR ${Math.round(h.rhr)} — high`);
    } else if (h.rhr <= base.rhr + 1) good++;
  }
  if (h.sleepH) {
    bits.push(`slept ${h.sleepH.toFixed(1)}h`);
    if (h.sleepH < 6) low++;
    else if (h.sleepH >= 7) good++;
  }
  if (deload) low++;
  if (!bits.length && !deload) return null;
  const joined = bits.join(' · ');
  const note = joined ? joined[0].toUpperCase() + joined.slice(1) : deload?.reason || '';
  if (low > 0) return { label: 'Fatigued', tone: 'low', note: deload?.reason || note };
  if (good >= 2) return { label: 'Rested', tone: 'good', note };
  return { label: 'Steady', tone: 'ok', note };
}

export const toneColor = (tone) =>
  tone === 'good' ? 'var(--green)' : tone === 'ok' ? 'var(--amber-text)' : 'var(--red)';

// ── Weekly target ──

/** Settings value, else a "N sessions a week" goal, else 3. */
export function weeklyTarget(settings = {}) {
  const t = Number(settings.weeklyTarget);
  if (t > 0) return Math.min(t, 14);
  const goal = goalProgress([], settings.goals).find((g) => g.unit === ' this week');
  if (goal?.target > 0) return Math.min(goal.target, 14);
  return 3;
}

// ── Ranges ──

/** Sessions / volume / kcal in the last `days` days, and sessions in the
 *  `days` before that (for the "+16%" delta). */
export function rangeSummary(history, days, bodyKg) {
  const start = daysAgoStr(days - 1);
  const prevStart = daysAgoStr(2 * days - 1);
  const cur = history.filter((s) => s.date >= start);
  const prev = history.filter((s) => s.date >= prevStart && s.date < start);
  return {
    sessions: cur.length,
    prevSessions: prev.length,
    volume: cur.reduce((a, s) => a + sessionVolume(s), 0),
    kcal: cur.reduce((a, s) => a + estimateSessionCalories(s, bodyKg), 0),
  };
}

/** Percent of the weekly target met over the last `weeks` weeks, capped at 100. */
export function compliance(history, weeks, target) {
  if (!(target > 0) || !(weeks > 0)) return 0;
  const done = history.filter((s) => s.date >= daysAgoStr(weeks * 7 - 1)).length;
  return Math.min(100, Math.round((done / (weeks * target)) * 100));
}

/** "+16%" style change; null when there's nothing to compare with. */
export const deltaPercent = (cur, prev) => (prev > 0 ? Math.round(((cur - prev) / prev) * 100) : null);

// ── Today's plan ──

const lastNumber = (s) => {
  const m = /(\d+)\D*$/.exec(String(s || ''));
  return m ? Number(m[1]) : null;
};

/** Expected kg lifted if every strength set hits the top of its rep
 *  range at the suggested (or last used) weight. */
export function projectedLoad(plan, history) {
  let total = 0;
  for (const ex of plan?.exercises || []) {
    if (logMode(ex.name, plan.sessionType) !== 'strength') continue;
    const reps = lastNumber(ex.reps) || 0;
    const last = lastPerformance(history, ex.name);
    const lastBest = Math.max(0, ...(last?.sets || []).map((s) => parseFloat(s.weight) || 0));
    const w = suggestNextWeight(last, ex.reps) || parseFloat(ex.suggestedWeight) || lastBest;
    total += (ex.sets || 0) * reps * w;
  }
  return Math.round(total);
}

/** Mean of the plan's RPE targets ("7-8" → 7.5), to the nearest half. */
export function averageRPE(plan) {
  const vals = (plan?.exercises || [])
    .map((ex) => {
      const m = /(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?/.exec(String(ex.rpe || ''));
      if (!m) return null;
      const n = [m[1], m[2]].filter(Boolean).map(Number);
      return n.reduce((a, b) => a + b, 0) / n.length;
    })
    .filter((v) => v != null);
  if (!vals.length) return null;
  return Math.round((vals.reduce((a, b) => a + b, 0) / vals.length) * 2) / 2;
}

/** 12400 → "12.4k" */
export const kgShort = (kg) => (kg >= 1000 ? `${(kg / 1000).toFixed(1).replace(/\.0$/, '')}k` : String(kg));

// ── Milestones ──

export function ladders(history) {
  const heaviest = Math.round(Math.max(0, ...prRecords(history).map((r) => r.weight?.w || 0)));
  const tonnes = Math.floor(history.reduce((a, s) => a + sessionVolume(s), 0) / 1000);
  return [
    { key: 'sessions', icon: 'calendar_month', value: history.length, steps: [10, 25, 50, 100, 250], title: (n) => `${n} Sessions` },
    { key: 'streak', icon: 'local_fire_department', value: weekStats(history).streak, steps: [2, 4, 8, 12, 26], title: (n) => `${n} Wk Streak` },
    { key: 'tonnes', icon: 'scale', value: tonnes, steps: [5, 10, 25, 50, 100], title: (n) => `${n}T Lifted` },
    { key: 'heaviest', icon: 'military_tech', value: heaviest, steps: [40, 60, 80, 100, 140], title: (n) => `${n} kg Lift` },
  ];
}

/** Every earned step plus the next one up on each ladder → [{ id, icon, title, value, goal, earned }] */
export function milestones(history) {
  return ladders(history).flatMap((l) => {
    const mk = (n) => ({ id: `${l.key}-${n}`, key: l.key, icon: l.icon, title: l.title(n), value: l.value, goal: n, earned: l.value >= n });
    const next = l.steps.find((n) => l.value < n);
    return [...l.steps.filter((n) => l.value >= n).map(mk), ...(next ? [mk(next)] : [])];
  });
}

/** The Records grid: each ladder's highest earned step and the next one up. */
export function keyMilestones(history) {
  const all = milestones(history);
  return ladders(history).flatMap((l) => {
    const mine = all.filter((m) => m.key === l.key);
    return [mine.filter((m) => m.earned).pop(), mine.find((m) => !m.earned)].filter(Boolean);
  });
}

/** The unearned milestone closest to done, for "next benchmark in reach". */
export function nextBenchmark(history) {
  return milestones(history)
    .filter((m) => !m.earned)
    .sort((a, b) => b.value / b.goal - a.value / a.goal)[0] || null;
}

// ── Notifications ──

/** When a session happened (ms): its start time, else noon that day. */
const sessionAt = (s) => s.startedAt || new Date(s.date + 'T12:00:00').getTime();

/** The in-app inbox, newest first: reviews, records set in the last two
 *  weeks, milestones crossed in the last month, a deload warning.
 *  Derived from data the app already has — nothing extra is stored except
 *  when you last looked (state `notifSeenAt`).
 *  → [{ id, icon, title, body, at, screen }] */
export function notifications(history, weekly, monthly) {
  const out = [];
  if (weekly?.text) {
    out.push({ id: `weekly-${weekly.week}`, icon: 'notifications', title: 'Weekly review ready', body: weekly.text.slice(0, 120), at: weekly.at || 0, screen: 'home' });
  }
  if (monthly?.text) {
    out.push({
      id: `monthly-${monthly.month}`, icon: 'calendar_month', title: 'Monthly report ready',
      body: `${monthly.sum?.count} sessions · ${monthly.sum?.volume?.toLocaleString()}kg lifted`, at: monthly.at || 0, screen: 'home',
    });
  }
  const sorted = [...history].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  const prCutoff = daysAgoStr(13);
  sorted.forEach((s, i) => {
    if (s.date < prCutoff) return;
    for (const pr of detectPRs(s, sorted.slice(0, i))) {
      out.push({
        id: `pr-${s.id || s.date}-${pr.name}-${pr.kind}`, icon: 'emoji_events', title: `New record: ${pr.name}`,
        body: `${pr.kind === 'weight' ? 'Heaviest set' : 'Est. 1RM'} ${pr.from} → ${pr.to}kg`, at: sessionAt(s), screen: 'records',
      });
    }
  });
  const msCutoff = daysAgoStr(29);
  for (const step of [10, 25, 50, 100, 250]) {
    const s = sorted[step - 1];
    if (s && s.date >= msCutoff) {
      out.push({ id: `ms-sessions-${step}`, icon: 'military_tech', title: `Milestone: ${step} sessions`, body: `Logged on ${fmtDate(s.date)}.`, at: sessionAt(s), screen: 'records' });
    }
  }
  const d = deloadSignal(history);
  if (d) {
    const wk = mondayOf(todayStr());
    out.push({ id: `deload-${wk}`, icon: 'warning', title: 'Deload suggested', body: d.reason, at: new Date(wk + 'T12:00:00').getTime(), screen: 'home' });
  }
  return out.sort((a, b) => b.at - a.at);
}

/** "2h", "3d", "Sep 12" */
export function ago(ms) {
  const s = (Date.now() - ms) / 1000;
  if (s < 3600) return `${Math.max(Math.floor(s / 60), 1)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  if (s < 7 * 86400) return `${Math.floor(s / 86400)}d`;
  return new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}
