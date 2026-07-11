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
const DB_VERSION = 3;

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

// ── Health log (daily Watch data) ────────────────────────────────

export function putHealth(entry) {
  if (!entry?.date) return Promise.resolve();
  return withStore('health', 'readwrite', (s) => s.put(entry));
}

export async function getAllHealth() {
  const rows = await withStore('health', 'readonly', (s) => s.getAll());
  return (rows || []).sort((a, b) => (a.date < b.date ? -1 : 1));
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
  };
}

/** Overwrite both stores with backup contents. No validation, no logging. */
export async function replaceAll(backup) {
  await withStore('sessions', 'readwrite', (s) => {
    s.clear();
    (backup.sessions || []).forEach(
      (row) => row && row.date && s.put({ ...row, id: sessionId(row) })
    );
  });
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
