// ── Apple Health auto-ingestion ──────────────────────────────────
// A web app can't talk to HealthKit directly (native-only API), so
// an iOS Shortcut reads the Watch's data and opens the app as
//   https://…/#health=<url-encoded text>
// We lift the payload out of the fragment (never sent to the server),
// store it per-day, and pre-fill the next check-in with it.

import { todayStr } from './helpers.js';

const KEY = 'coach:health-';

/**
 * Parse health data from the URL — either ?health=… (query, survives
 * everything and forces a real page load) or #health=… (fragment,
 * never sent to the server). Store it for today.
 * Returns the ingested text, or null if neither was present.
 */
export function ingestHealthFromUrl(
  hash = window.location.hash,
  store = localStorage,
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
  return text;
}

/** Health text received for today (from the Shortcut), or ''. */
export function todaysHealth(store = localStorage) {
  return store.getItem(KEY + todayStr()) || '';
}

/** Drop stored payloads older than today (they're single-use). */
export function pruneOldHealth(store = localStorage) {
  const today = KEY + todayStr();
  for (let i = store.length - 1; i >= 0; i--) {
    const k = store.key(i);
    if (k && k.startsWith(KEY) && k !== today) store.removeItem(k);
  }
}
