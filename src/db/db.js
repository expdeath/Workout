// ── IndexedDB persistence layer ──────────────────────────────────
// Replaces localStorage for training data. Two stores:
//   sessions — one record per training day (keyPath: date)
//   events   — append-only log of every interaction (check-ins,
//              AI requests/responses, errors, finishes, imports…)
// The full history lives here uncapped; the AI context builder
// summarizes it so old data keeps informing new plans.

const DB_NAME = 'coach-db';
// v2: sessions keyed by unique id instead of date, so multiple
// workouts on the same day no longer overwrite each other
// v3: health store — one row per day of Watch data (HRV/RHR/steps)
// v4: media store — per-exercise form photos/clips (device-local only:
//     blobs are far too big for the GitHub-JSON backup)
const DB_VERSION = 4;

export const sessionId = (s) => s.id || s.date;

let dbPromise = null;

function openDb() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (ev) => {
      const db = req.result;
      if (!db.objectStoreNames.contains('events')) {
        const evs = db.createObjectStore('events', {
          keyPath: 'id',
          autoIncrement: true,
        });
        evs.createIndex('ts', 'ts');
        evs.createIndex('type', 'type');
      }
      if (ev.oldVersion < 3 && !db.objectStoreNames.contains('health')) {
        db.createObjectStore('health', { keyPath: 'date' });
      }
      if (ev.oldVersion < 4 && !db.objectStoreNames.contains('media')) {
        db.createObjectStore('media', { keyPath: 'key' });
      }
      if (ev.oldVersion < 2) {
        if (db.objectStoreNames.contains('sessions')) {
          // re-key existing rows: date → id (legacy rows keep id = date)
          const old = req.transaction.objectStore('sessions');
          const getAll = old.getAll();
          getAll.onsuccess = () => {
            const rows = getAll.result || [];
            db.deleteObjectStore('sessions');
            const ns = db.createObjectStore('sessions', { keyPath: 'id' });
            rows.forEach((r) => {
              if (r && r.date) ns.put({ ...r, id: sessionId(r) });
            });
          };
        } else {
          db.createObjectStore('sessions', { keyPath: 'id' });
        }
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function withStore(storeName, mode, fn) {
  return openDb().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, mode);
        const store = tx.objectStore(storeName);
        const result = fn(store);
        tx.oncomplete = () =>
          resolve(result && 'result' in result ? result.result : undefined);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      })
  );
}

// ── Sessions ─────────────────────────────────────────────────────

export async function getAllSessions() {
  const rows = await withStore('sessions', 'readonly', (s) => s.getAll());
  // chronological: by date, then by id (ids embed creation time)
  return (rows || []).sort((a, b) =>
    (a.date + sessionId(a)).localeCompare(b.date + sessionId(b))
  );
}

export function putSession(session) {
  // updatedAt lets cloud sync pick the newer copy on merge conflicts
  return withStore('sessions', 'readwrite', (s) =>
    s.put({ ...session, id: sessionId(session), updatedAt: Date.now() })
  );
}

export function clearSessions() {
  return withStore('sessions', 'readwrite', (s) => s.clear());
}

// ── Deletion log ─────────────────────────────────────────────────
// Deleted sessions are REMOVED from the store; only their id+time go
// on this list so the deletion propagates to other devices through
// sync instead of the session resurrecting. Markers are kept
// permanently (a few bytes each).

const DELETED_KEY = 'coach:deleted-ids';

export function getDeletedIds() {
  try {
    return JSON.parse(localStorage.getItem(DELETED_KEY)) || [];
  } catch {
    return [];
  }
}

export function setDeletedIds(list) {
  try {
    localStorage.setItem(DELETED_KEY, JSON.stringify(list || []));
  } catch { /* non-critical */ }
}

/** Remove the session row for real and record the deletion. */
export async function hardDeleteSession(id) {
  await withStore('sessions', 'readwrite', (s) => s.delete(id));
  const list = getDeletedIds().filter((d) => d.id !== id);
  list.push({ id, at: Date.now() });
  setDeletedIds(list);
}

// ── Health log (daily Watch data) ────────────────────────────────

export function putHealth(entry) {
  if (!entry?.date) return Promise.resolve();
  return withStore('health', 'readwrite', (s) => s.put(entry));
}

export async function getAllHealth() {
  const rows = await withStore('health', 'readonly', (s) => s.getAll());
  return (rows || []).sort((a, b) => (a.date < b.date ? -1 : 1));
}

/** Patch a day's row without clobbering fields another source wrote
 *  (Watch data and a typed body weight share the same date row). */
export async function mergeHealth(patch) {
  if (!patch?.date) return;
  const existing = await withStore('health', 'readonly', (s) => s.get(patch.date));
  await putHealth({ ...(existing || {}), ...patch, receivedAt: Date.now() });
}

// ── Exercise media (device-local, never synced) ──────────────────
// One photo or short clip per exercise, keyed like cue notes
// (lowercased exercise name). Blobs stay in IndexedDB on this device.

export async function putMedia(key, blob, type) {
  return withStore('media', 'readwrite', (s) =>
    s.put({ key, blob, type, updatedAt: Date.now() })
  );
}

export async function getMedia(key) {
  try {
    return await withStore('media', 'readonly', (s) => s.get(key));
  } catch {
    return null;
  }
}

export async function deleteMedia(key) {
  return withStore('media', 'readwrite', (s) => s.delete(key));
}

// ── Event log ────────────────────────────────────────────────────
// Never throws — a logging failure must not break a workout.

export async function logEvent(type, data = {}) {
  try {
    const now = new Date();
    await withStore('events', 'readwrite', (s) =>
      s.add({ ts: now.getTime(), iso: now.toISOString(), type, data })
    );
  } catch (e) {
    console.warn('[COACH] event log failed', e);
  }
}

export async function countEvents() {
  try {
    return (await withStore('events', 'readonly', (s) => s.count())) || 0;
  } catch {
    return 0;
  }
}

async function getAllEvents() {
  const rows = await withStore('events', 'readonly', (s) => s.getAll());
  return rows || [];
}

// ── Backup: export / import ──────────────────────────────────────

import { getAISettings, restoreAISettings } from '../utils/storage.js';

export async function exportAll() {
  const [sessions, events, health] = await Promise.all([
    getAllSessions(),
    getAllEvents(),
    getAllHealth(),
  ]);
  return {
    app: 'coach',
    version: DB_VERSION,
    exportedAt: new Date().toISOString(),
    sessions,
    events,
    health,
    aiSettings: getAISettings(),
    deletedIds: getDeletedIds(),
  };
}

/** Overwrite both stores with backup contents. No validation, no logging. */
export async function replaceAll(backup) {
  const dels = new Set((backup.deletedIds || []).map((d) => d.id));
  await withStore('sessions', 'readwrite', (s) => {
    s.clear();
    (backup.sessions || []).forEach(
      (row) =>
        row && row.date && !row.deleted && !dels.has(sessionId(row)) &&
        s.put({ ...row, id: sessionId(row) })
    );
  });
  if (backup.deletedIds) setDeletedIds(backup.deletedIds);
  await withStore('events', 'readwrite', (s) => {
    s.clear();
    (backup.events || []).forEach(({ id, ...row }) => row && row.type && s.add(row));
  });
  await withStore('health', 'readwrite', (s) => {
    s.clear();
    (backup.health || []).forEach((row) => row && row.date && s.put(row));
  });
  if (backup.aiSettings && (backup.aiSettings.updatedAt || 0) > (getAISettings().updatedAt || 0)) {
    restoreAISettings(backup.aiSettings);
  }
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

// ── One-time migration from localStorage ─────────────────────────

export async function migrateFromLocalStorage() {
  try {
    if (localStorage.getItem('coach:migrated-idb')) return;
    const raw = localStorage.getItem('coach:history');
    const old = raw ? JSON.parse(raw) : [];
    const existing = await withStore('sessions', 'readonly', (s) => s.count());
    if (Array.isArray(old) && old.length && !existing) {
      await withStore('sessions', 'readwrite', (s) => {
        old.forEach((row) => row && row.date && s.put({ ...row, id: sessionId(row) }));
      });
      await logEvent('migrated_from_localstorage', { sessions: old.length });
    }
    localStorage.setItem('coach:migrated-idb', '1');
  } catch (e) {
    console.warn('[COACH] migration failed', e);
  }
}
