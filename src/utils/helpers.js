// ── Date formatters & readiness calculation ─────────────────────

// A set counts if it was ticked done OR has data typed into it —
// entering weight/reps clearly means the set happened
export const setLogged = (s) => !!(s && (s.done || s.weight || s.reps));

// ── Set-input sanitation ─────────────────────────────────────────
// Clamp instead of reject: typos like 1000kg become 200, "88 reps"
// becomes 30 — nothing silly reaches the log, charts, or the AI.
export const MAX_WEIGHT_KG = 200;
export const MAX_REPS = 30;

export function cleanWeight(v) {
  let s = String(v ?? '').replace(/[^\d.]/g, '');
  const firstDot = s.indexOf('.');
  if (firstDot !== -1) {
    s = s.slice(0, firstDot + 1) + s.slice(firstDot + 1).replace(/\./g, '').slice(0, 2);
  }
  if (s === '') return '';
  const n = parseFloat(s);
  if (!Number.isNaN(n) && n > MAX_WEIGHT_KG) return String(MAX_WEIGHT_KG);
  return s;
}

export function cleanReps(v) {
  const s = String(v ?? '').replace(/\D/g, '');
  if (!s) return '';
  return String(Math.min(parseInt(s, 10), MAX_REPS));
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
