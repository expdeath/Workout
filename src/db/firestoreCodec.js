// ── Backup ⇄ Firestore documents (pure, no SDK) ──────────────────
// One account's data maps onto Firestore like this (see
// docs/firestore.md for the full schema + rules):
//
//   accounts/{accountId}                     { name, backupMeta, github… }
//   accounts/{accountId}/sessions/{id}        one workout
//   accounts/{accountId}/health/{date}        one day of Watch data
//   accounts/{accountId}/deletedIds/{id}      deletion marker { id, at }
//   accounts/{accountId}/events/{iso|type}    one event-log entry
//   accounts/{accountId}/state/aiSettings     profile/routine/gym setup
//
// Firestore can't hold an array directly inside an array (a session's
// `log` is [[set,…],…]) and reserves some field names, so values go
// through encodeValue/decodeValue — lossless for any JSON value.
// Used by scripts/migrate-to-firestore.js and the web app; the iOS
// port lives in ios/CoachApp/CoachApp/Sync/FirestoreCodec.swift.

import { normalizeBackup } from './backupShape.js';

const ARR = '__a'; // { __a: [...] }        an array that sat inside an array
const MAP = '__m'; // { __m: [{k, v}, …] }  an object with keys Firestore can't hold

// '' and any key starting with "__" (reserved by Firestore and by this
// codec's own markers) force the escaped form for that whole object
const badKey = (k) => k === '' || k.startsWith('__');

export function encodeValue(v, inArray = false) {
  if (Array.isArray(v)) {
    const arr = v.map((x) => encodeValue(x, true));
    return inArray ? { [ARR]: arr } : arr;
  }
  if (v && typeof v === 'object') {
    const keys = Object.keys(v);
    if (keys.some(badKey)) {
      return { [MAP]: keys.map((k) => ({ k, v: encodeValue(v[k]) })) };
    }
    const out = {};
    for (const k of keys) if (v[k] !== undefined) out[k] = encodeValue(v[k]);
    return out;
  }
  return v;
}

export function decodeValue(v) {
  if (Array.isArray(v)) return v.map(decodeValue);
  if (v && typeof v === 'object') {
    const keys = Object.keys(v);
    if (keys.length === 1 && keys[0] === ARR) return decodeValue(v[ARR]);
    if (keys.length === 1 && keys[0] === MAP) {
      const out = {};
      for (const { k, v: x } of v[MAP]) out[k] = decodeValue(x);
      return out;
    }
    const out = {};
    for (const k of keys) out[k] = decodeValue(v[k]);
    return out;
  }
  return v;
}

// Document ids can't contain "/" or be "." / ".." / "__…__"; the real
// key always also lives inside the document, so ids are just lookups.
export function docId(raw) {
  const s = String(raw ?? '');
  const esc = s.replace(/%/g, '%25').replace(/\//g, '%2F');
  if (esc === '' || esc === '.' || esc === '..' || /^__.*__$/.test(esc)) {
    return `%${esc}`;
  }
  return esc;
}

// same key sync.js mergeBackups() dedupes the event log by
export const eventDocId = (e) => docId(`${e.iso}|${e.type}`);

/**
 * Normalized backup → the documents for one account.
 * Returns { meta, docs: [{ col, id, data }] } where col is the
 * subcollection under accounts/{accountId} ('' = the account doc's
 * `state` singletons live under col 'state').
 */
export function backupToDocs(backup) {
  const b = normalizeBackup(backup);
  const docs = [];
  for (const s of b.sessions) docs.push({ col: 'sessions', id: docId(s.id), data: encodeValue(s) });
  for (const h of b.health) docs.push({ col: 'health', id: docId(h.date), data: encodeValue(h) });
  for (const d of b.deletedIds) docs.push({ col: 'deletedIds', id: docId(d.id), data: encodeValue(d) });
  for (const e of b.events) docs.push({ col: 'events', id: eventDocId(e), data: encodeValue(e) });
  docs.push({ col: 'state', id: 'aiSettings', data: encodeValue(b.aiSettings) });
  return { meta: { app: b.app, version: b.version }, docs };
}

/**
 * Inverse of backupToDocs: { meta, docs } (as read back from
 * Firestore) → a normalized backup, comparable as a JSON string with
 * normalizeBackup(original).
 */
export function docsToBackup({ meta = {}, docs }) {
  const by = (col) => docs.filter((d) => d.col === col).map((d) => decodeValue(d.data));
  const ai = docs.find((d) => d.col === 'state' && d.id === 'aiSettings');
  return normalizeBackup({
    app: meta.app || 'coach',
    version: meta.version,
    aiSettings: ai ? decodeValue(ai.data) : {},
    deletedIds: by('deletedIds'),
    health: by('health'),
    sessions: by('sessions'),
    events: by('events'),
  });
}
