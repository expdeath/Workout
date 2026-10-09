// ── Persistence layer ────────────────────────────────────────────
// Training data lives in Cloud Firestore (cloud.js keeps an in-memory
// mirror of the signed-in account, live across devices):
//   sessions   — one record per workout (id = `${date}#${startedAt}`)
//   health     — one row per day of Watch data
//   events     — append-only log of every interaction (write-only here)
//   deletedIds — permanent deletion markers
// Exercise form photos/clips stay on this device only, in IndexedDB
// (`media` store) — far too big for the database.

import {
  cloudSessions,
  cloudPutSession,
  cloudDeleteSession,
  cloudClearSessions,
  cloudHealth,
  cloudPutHealth,
  cloudDeletedIds,
  cloudLogEvent,
  cloudCountEvents,
  cloudAllEvents,
  cloudReplaceData,
  cloudState,
  cloudStateKeys,
  cloudSetState,
} from './cloud.js';
import { normalizeBackup } from './backupShape.js';

export const sessionId = (s) => s.id || s.date;

// ── Sessions ─────────────────────────────────────────────────────

// chronological: by date, then by id (ids embed creation time)
export const sortSessions = (rows) =>
  [...(rows || [])].sort((a, b) =>
    (a.date + sessionId(a)).localeCompare(b.date + sessionId(b))
  );

export async function getAllSessions() {
  return sortSessions(cloudSessions());
}

export function putSession(session) {
  // updatedAt: a write can't overwrite a newer copy (firestore.rules)
  return cloudPutSession({ ...session, id: sessionId(session), updatedAt: Date.now() });
}

export function clearSessions() {
  return cloudClearSessions();
}

// ── Deletion log ─────────────────────────────────────────────────
// Deleted sessions are REMOVED; a permanent marker per id stops any
// device (however long offline) from bringing them back.

export const getDeletedIds = () => cloudDeletedIds();

/** Remove the session for real and record the deletion. */
export function hardDeleteSession(id) {
  return cloudDeleteSession(id);
}

// ── Health log (daily Watch data) ────────────────────────────────

export function putHealth(entry) {
  if (!entry?.date) return Promise.resolve();
  return cloudPutHealth(entry);
}

export async function getAllHealth() {
  return cloudHealth().sort((a, b) => (a.date < b.date ? -1 : 1));
}

/** Patch a day's row without clobbering fields another source wrote
 *  (Watch data and a typed body weight share the same date row). */
export async function mergeHealth(patch) {
  if (!patch?.date) return;
  const existing = cloudHealth().find((h) => h.date === patch.date);
  await putHealth({ ...(existing || {}), ...patch, receivedAt: Date.now() });
}

// ── Exercise media (device-local, never synced) ──────────────────
// One photo or short clip per exercise, keyed like cue notes
// (lowercased exercise name). Same IndexedDB database/version as
// before, so existing media survives the move to Firestore.

const DB_NAME = 'coach-db';
const DB_VERSION = 4;
let dbPromise = null;

function openDb() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains('media')) {
        req.result.createObjectStore('media', { keyPath: 'key' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function withMedia(mode, fn) {
  return openDb().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction('media', mode);
        const result = fn(tx.objectStore('media'));
        tx.oncomplete = () => resolve(result && 'result' in result ? result.result : undefined);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      })
  );
}

export async function putMedia(key, blob, type) {
  return withMedia('readwrite', (s) => s.put({ key, blob, type, updatedAt: Date.now() }));
}

export async function getMedia(key) {
  try {
    return await withMedia('readonly', (s) => s.get(key));
  } catch {
    return null;
  }
}

export async function deleteMedia(key) {
  return withMedia('readwrite', (s) => s.delete(key));
}

// ── Event log ────────────────────────────────────────────────────
// Never throws — a logging failure must not break a workout.

export async function logEvent(type, data = {}) {
  try {
    const now = new Date();
    await cloudLogEvent({ ts: now.getTime(), iso: now.toISOString(), type, data });
  } catch (e) {
    console.warn('[COACH] event log failed', e);
  }
}

export const countEvents = () => cloudCountEvents();

// ── Backup: export / import ──────────────────────────────────────

export async function exportAll() {
  return {
    app: 'coach',
    version: DB_VERSION,
    exportedAt: new Date().toISOString(),
    sessions: await getAllSessions(),
    events: await cloudAllEvents(),
    health: await getAllHealth(),
    aiSettings: cloudState('aiSettings', {}),
    deletedIds: getDeletedIds(),
    // saved workouts + preferences: in the export file (not yet in the
    // GitHub backup — the iOS app's backup format doesn't know them)
    workouts: cloudStateKeys().filter((k) => k.startsWith('workout-')).map((k) => cloudState(k)).filter(Boolean),
    prefs: cloudState('prefs', null),
  };
}

/** Make the cloud match a backup: sessions/health replaced, events and
 *  deletion markers added, AI settings only if the backup's are newer. */
export async function replaceAll(backup) {
  await cloudReplaceData(normalizeBackup(backup));
  const cur = cloudState('aiSettings', {});
  if (backup.aiSettings && (backup.aiSettings.updatedAt || 0) > (cur.updatedAt || 0)) {
    await cloudSetState('aiSettings', backup.aiSettings);
  }
  // saved workouts: add missing ones, newer copies win
  for (const w of Array.isArray(backup.workouts) ? backup.workouts : []) {
    if (!w?.id) continue;
    const have = cloudState(`workout-${w.id}`, null);
    if (!have || (w.updatedAt || 0) > (have.updatedAt || 0)) cloudSetState(`workout-${w.id}`, w);
  }
  if (backup.prefs && !cloudState('prefs', null)) cloudSetState('prefs', backup.prefs);
}

/** Restore a backup, replacing current data. Throws on invalid shape. */
export async function importAll(backup) {
  if (!backup || !Array.isArray(backup.sessions)) {
    throw new Error('Not a valid COACH backup file.');
  }
  await replaceAll(backup);
  await logEvent('data_imported', {
    sessions: backup.sessions.length,
    events: backup.events?.length || 0,
    exportedAt: backup.exportedAt,
  });
}
