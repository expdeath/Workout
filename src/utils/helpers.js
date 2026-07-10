// ── Date formatters & readiness calculation ─────────────────────

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
