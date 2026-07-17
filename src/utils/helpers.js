// ── Date formatters & readiness calculation ─────────────────────

// A set counts if it was ticked done OR has data typed into it —
// entering weight/reps (or min/km on cardio) clearly means it happened
export const setLogged = (s) =>
  !!(s && (s.done || s.weight || s.reps || s.time || s.dist));

/**
 * One logged set as text. Cardio sets carry time/dist ("30min · 5km"),
 * strength sets carry weight/reps ("60kg×8").
 */
export function fmtSet(s) {
  if (s?.time || s?.dist) {
    return [s.time ? `${s.time}min` : '', s.dist ? `${s.dist}km` : '']
      .filter(Boolean)
      .join(' · ');
  }
  return `${s?.weight || '?'}kg×${s?.reps || '?'}`;
}

// ── Set-input sanitation ─────────────────────────────────────────
// Clamp instead of reject: typos like 1000kg become 200, "88 reps"
// becomes 30 — nothing silly reaches the log, charts, or the AI.
export const MAX_WEIGHT_KG = 200;
export const MAX_REPS = 30;
export const MAX_TIME_MIN = 300;
export const MAX_DIST_KM = 100;

function cleanDecimal(v, max) {
  let s = String(v ?? '').replace(/[^\d.]/g, '');
  const firstDot = s.indexOf('.');
  if (firstDot !== -1) {
    s = s.slice(0, firstDot + 1) + s.slice(firstDot + 1).replace(/\./g, '').slice(0, 2);
  }
  if (s === '') return '';
  const n = parseFloat(s);
  if (!Number.isNaN(n) && n > max) return String(max);
  return s;
}

export const cleanWeight = (v) => cleanDecimal(v, MAX_WEIGHT_KG);
export const cleanTime = (v) => cleanDecimal(v, MAX_TIME_MIN);
export const cleanDist = (v) => cleanDecimal(v, MAX_DIST_KM);

export function cleanReps(v) {
  const s = String(v ?? '').replace(/\D/g, '');
  if (!s) return '';
  return String(Math.min(parseInt(s, 10), MAX_REPS));
}

// ── Plate math ───────────────────────────────────────────────────
export const DEFAULT_BAR_KG = 20;
export const DEFAULT_PLATES = [25, 20, 15, 10, 5, 2.5, 1.25];

/** "25, 20, 2.5" → [25, 20, 2.5] (deduped, largest first), or null. */
export function parsePlates(text) {
  const list = String(text || '')
    .split(/[,\s]+/)
    .map(parseFloat)
    .filter((n) => !Number.isNaN(n) && n > 0 && n <= 50);
  return list.length ? [...new Set(list)].sort((a, b) => b - a) : null;
}

/**
 * Greedy per-side barbell breakdown for a target total weight.
 * Returns { bar, perSide, loaded, exact } — `loaded` is the closest
 * achievable total when the plates can't hit the target exactly —
 * or null when the target isn't a positive number.
 */
export function plateBreakdown(target, barKg = DEFAULT_BAR_KG, plates = DEFAULT_PLATES) {
  const t = parseFloat(target);
  if (Number.isNaN(t) || t <= 0) return null;
  if (t <= barKg) return { bar: barKg, perSide: [], loaded: barKg, exact: t === barKg };
  let side = (t - barKg) / 2;
  const perSide = [];
  for (const p of [...plates].sort((a, b) => b - a)) {
    while (side >= p - 1e-9) {
      perSide.push(p);
      side -= p;
    }
  }
  const loaded = barKg + 2 * perSide.reduce((a, b) => a + b, 0);
  return { bar: barKg, perSide, loaded, exact: Math.abs(loaded - t) < 0.05 };
}

export const todayStr = () => new Date().toISOString().slice(0, 10);

export const fmtDate = (iso) =>
  new Date(iso + 'T12:00:00').toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });

// Quick readiness estimate (client-side, pre-AI)
export function quickReadiness(c) {
  let s = 50;
  s += (c.energy - 5) * 5;
  if (c.sleep === 'Great') s += 15;
  if (c.sleep === 'OK') s += 5;
  if (c.sleep === 'Poor') s -= 15;
  if (c.soreness === 'None') s += 10;
  if (c.soreness === 'Light') s -= 5;
  if (c.soreness === 'Very sore') s -= 20;
  if (c.backTight) s -= 8;
  return Math.max(5, Math.min(98, Math.round(s)));
}
