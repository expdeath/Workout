// ── Calorie estimation ───────────────────────────────────────────
// MET-based estimate, computed on the fly from existing session/health
// data — nothing is persisted, so old history gets estimates for free
// and the IndexedDB schema never has to change.

const MET_BY_SESSION_TYPE = {
  Run: 9.8,
  Cycle: 7.5,
  Walk: 4.3,
  Hike: 6.0,
  Cardio: 7.0,
  'Active Recovery': 4.0,
  'Stretch & Mobility': 2.5,
  Push: 5.0,
  Pull: 5.0,
  Legs: 5.0,
  'Full Body': 5.0,
  Core: 5.0,
};
const DEFAULT_MET = 4.0;
const DEFAULT_BODY_KG = 75;

/** Most recent known body weight across the health log, kg. */
export function latestBodyWeightKg(healthRows, fallback = DEFAULT_BODY_KG) {
  let best = null;
  for (const h of healthRows || []) {
    if (h?.weightKg && (best === null || h.date > best.date)) best = h;
  }
  return best ? best.weightKg : fallback;
}

/** Estimated calories burned for one session, given a body weight. */
export function estimateSessionCalories(session, bodyKg = DEFAULT_BODY_KG) {
  const sessionType = session?.plan?.sessionType;
  if (!sessionType || sessionType === 'Rest Day') return 0;
  const met = MET_BY_SESSION_TYPE[sessionType] ?? DEFAULT_MET;
  const durationMin = session.durationMin || session.plan?.estTimeMin || 0;
  if (!durationMin) return 0;
  return Math.round(met * bodyKg * (durationMin / 60));
}

/** { thisWeek, allTime } estimated-calorie totals across history. */
export function calorieStats(history, bodyKg = DEFAULT_BODY_KG) {
  const weekAgo = Date.now() - 7 * 86400000;
  let thisWeek = 0;
  let allTime = 0;
  for (const s of history || []) {
    const kcal = estimateSessionCalories(s, bodyKg);
    allTime += kcal;
    if (new Date(s.date + 'T12:00:00').getTime() >= weekAgo) thisWeek += kcal;
  }
  return { thisWeek: Math.round(thisWeek), allTime: Math.round(allTime) };
}
