// ── Apple Health auto-ingestion ──────────────────────────────────
// A web app can't talk to HealthKit directly (native-only API), so
// an iOS Shortcut reads the Watch's data and opens the app as
//   https://…/#health=<url-encoded text>
// We lift the payload out of the fragment (never sent to the server),
// store it per-day, and pre-fill the next check-in with it.

import { todayStr } from './helpers.js';
import { parseHealthNumbers } from './stats.js';
import { mergeHealth, getAllHealth } from '../db/db.js';
import { cloudState, cloudSetState, cloudStateKeys } from '../db/cloud.js';

// Today's raw Watch text lives in the account's state as
// healthText-<date> (Firestore), so every device sees it.
const KEY = 'healthText-';
const cloudStore = {
  getItem: (k) => cloudState(k, null),
  setItem: (k, v) => cloudSetState(k, v),
};

/** Persist the day's parsed numbers into the health store (synced). */
function recordHealth(text) {
  try {
    const nums = parseHealthNumbers(text);
    if (Object.values(nums).some(Boolean)) {
      const row = { date: todayStr(), raw: text.slice(0, 300) };
      // only write fields this payload actually carries — a partial
      // payload must not null out values an earlier one delivered
      for (const [k, v] of Object.entries(nums)) if (v) row[k] = v;
      mergeHealth(row).catch(() => {});
    }
  } catch { /* parsing is best-effort */ }
}

/**
 * Parse health data from the URL — either ?health=… (query, survives
 * everything and forces a real page load) or #health=… (fragment,
 * never sent to the server). Store it for today.
 * Returns the ingested text, or null if neither was present.
 */
export function ingestHealthFromUrl(
  hash = window.location.hash,
  store = cloudStore,
  search = typeof window !== 'undefined' ? window.location.search : ''
) {
  let raw = null;
  const m = /^#health=(.+)$/.exec(hash || '');
  if (m) raw = m[1];
  if (raw === null && search) {
    const q = new URLSearchParams(search).get('health');
    if (q) raw = encodeURIComponent(q); // URLSearchParams already decoded it
  }
  if (raw === null) return null;
  let text;
  try {
    text = decodeURIComponent(raw);
  } catch {
    text = raw;
  }
  text = text.replace(/\+/g, ' ').trim().slice(0, 2000);
  if (!text) return null;
  store.setItem(KEY + todayStr(), text);
  recordHealth(text);
  return text;
}

/** Health text received for today (from the Shortcut), or ''. */
export function todaysHealth(store = cloudStore) {
  return store.getItem(KEY + todayStr()) || '';
}

/** Persist health text for today (clipboard paste path). */
export function storeTodaysHealth(text, store = cloudStore) {
  const t = (text || '').trim().slice(0, 2000);
  if (t) {
    store.setItem(KEY + todayStr(), t);
    recordHealth(t);
  }
  return t;
}

/** Heuristic: does clipboard text look like Watch/Health data? */
export function looksLikeHealthData(text) {
  if (!text || text.length > 600) return false;
  return /\b(hrv|rhr|steps|sleep|bpm|resting|heart|vo2|spo2|kcal)\b/i.test(text) && /\d/.test(text);
}

/**
 * Re-parse every stored raw payload with the current parser and fill
 * fields the row is missing. Runs cheaply at boot, so parser upgrades
 * (new metrics, unit fixes) apply to already-ingested days without
 * re-running the Watch shortcut.
 */
export async function reparseHealthRows() {
  try {
    for (const r of await getAllHealth()) {
      if (!r?.raw) continue;
      const nums = parseHealthNumbers(r.raw);
      const fill = Object.fromEntries(
        Object.entries(nums).filter(
          ([k, v]) =>
            v &&
            // fill missing fields; also repair sleep rows stored before
            // the double-source dedupe existed
            (r[k] == null || (k === 'sleepH' && r[k] > 11))
        )
      );
      if (Object.keys(fill).length) await mergeHealth({ date: r.date, ...fill });
    }
  } catch (e) {
    console.warn('[COACH] health re-parse failed', e);
  }
}

/** Drop stored payloads older than today (they're single-use). */
export function pruneOldHealth() {
  const today = KEY + todayStr();
  for (const k of cloudStateKeys()) {
    if (k.startsWith(KEY) && k !== today) cloudSetState(k, null);
  }
}
