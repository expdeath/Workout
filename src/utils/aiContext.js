// ── Long-term AI context builder ─────────────────────────────────
// The prompt already includes the last 6 sessions in full detail.
// This module compresses EVERYTHING OLDER into a compact summary —
// per-exercise progression, weekly adherence, split balance, pain
// patterns, RPE trend — so years of history fit in a few hundred
// tokens and old data keeps steering today's plan.

const MAX_CHARS = 1800;

function bestWeight(session, exIndex) {
  const sets = (session.log?.[exIndex] || []).filter((s) => s.done);
  let best = null;
  for (const s of sets) {
    const w = parseFloat(s.weight);
    if (!Number.isNaN(w) && (best === null || w > best)) best = w;
  }
  return best;
}

export function buildLongTermSummary(sessions) {
  if (!Array.isArray(sessions) || sessions.length < 5) return '';
  const lines = [];

  // Totals
  const first = sessions[0].date;
  lines.push(`${sessions.length} sessions logged since ${first}.`);

  // Weekly adherence, last 8 weeks (oldest → newest)
  const weekMs = 7 * 86400000;
  const now = Date.now();
  const weeks = Array.from({ length: 8 }, () => 0);
  for (const s of sessions) {
    const age = now - new Date(s.date + 'T12:00:00').getTime();
    const w = Math.floor(age / weekMs);
    if (w >= 0 && w < 8) weeks[7 - w]++;
  }
  lines.push(`Sessions per week, last 8 weeks (oldest→newest): ${weeks.join(', ')}.`);

  // Split balance, last 90 days
  const cutoff = now - 90 * 86400000;
  const split = {};
  for (const s of sessions) {
    if (new Date(s.date + 'T12:00:00').getTime() < cutoff) continue;
    const t = s.plan?.sessionType || 'Other';
    split[t] = (split[t] || 0) + 1;
  }
  const splitTxt = Object.entries(split)
    .sort((a, b) => b[1] - a[1])
    .map(([t, n]) => `${t} ${n}`)
    .join(', ');
  if (splitTxt) lines.push(`Split last 90 days: ${splitTxt}.`);

  // Per-exercise progression across ALL history
  const byExercise = new Map();
  for (const s of sessions) {
    (s.plan?.exercises || []).forEach((ex, i) => {
      if (!ex?.name) return;
      const w = bestWeight(s, i);
      if (w === null) return;
      const key = ex.name.trim().toLowerCase();
      if (!byExercise.has(key)) byExercise.set(key, { name: ex.name.trim(), points: [] });
      byExercise.get(key).points.push({ date: s.date, w });
    });
  }
  const top = [...byExercise.values()]
    .filter((e) => e.points.length >= 2)
    .sort((a, b) => b.points.length - a.points.length)
    .slice(0, 12);
  if (top.length) {
    lines.push('Exercise progression (first → latest, best, times done):');
    for (const e of top) {
      const firstW = e.points[0].w;
      const last = e.points[e.points.length - 1];
      const best = Math.max(...e.points.map((p) => p.w));
      lines.push(
        `- ${e.name}: ${firstW}kg → ${last.w}kg (best ${best}kg, ${e.points.length}x, last ${last.date})`
      );
    }
  }

  // Recurring pain reports
  const pains = {};
  for (const s of sessions) {
    const p = s.fin?.pain?.trim().toLowerCase();
    if (p) pains[p] = (pains[p] || 0) + 1;
  }
  const painTxt = Object.entries(pains)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([p, n]) => `"${p}" x${n}`)
    .join(', ');
  if (painTxt) lines.push(`Recurring pain reports: ${painTxt}.`);

  // RPE trend
  const rpes = sessions
    .filter((s) => s.finished && s.fin?.rpe != null)
    .map((s) => Number(s.fin.rpe))
    .filter((n) => !Number.isNaN(n));
  if (rpes.length >= 6) {
    const avg = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
    const recent = avg(rpes.slice(-5)).toFixed(1);
    const prior = avg(rpes.slice(0, -5)).toFixed(1);
    lines.push(`Avg session RPE: last 5 = ${recent}, all prior = ${prior}.`);
  }

  let out = lines.join('\n');
  if (out.length > MAX_CHARS) out = out.slice(0, MAX_CHARS) + '…';
  return out;
}
