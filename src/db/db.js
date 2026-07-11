// ── IndexedDB persistence layer ──────────────────────────────────
// Replaces localStorage for training data. Two stores:
//   sessions — one record per training day (keyPath: date)
//   events   — append-only log of every interaction (check-ins,
//              AI requests/responses, errors, finishes, imports…)
// The full history lives here uncapped; the AI context builder
// summarizes it so old data keeps informing new plans.

const DB_NAME = 'coach-db';
const DB_VERSION = 1;

let dbPromise = null;

function openDb() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('sessions')) {
        db.createObjectStore('sessions', { keyPath: 'date' });
      }
      if (!db.objectStoreNames.contains('events')) {
        const ev = db.createObjectStore('events', {
          keyPath: 'id',
          autoIncrement: true,
        });
        ev.createIndex('ts', 'ts');
        ev.createIndex('type', 'type');
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
  return (rows || []).sort((a, b) => (a.date < b.date ? -1 : 1));
}

export function putSession(session) {
  return withStore('sessions', 'readwrite', (s) => s.put(session));
}

export function clearSessions() {
  return withStore('sessions', 'readwrite', (s) => s.clear());
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

export async function exportAll() {
  const [sessions, events] = await Promise.all([
    getAllSessions(),
    getAllEvents(),
  ]);
  return {
    app: 'coach',
    version: DB_VERSION,
    exportedAt: new Date().toISOString(),
    sessions,
    events,
  };
}

/** Restore a backup, replacing current data. Throws on invalid shape. */
export async function importAll(backup) {
  if (!backup || !Array.isArray(backup.sessions)) {
    throw new Error('Not a valid COACH backup file.');
  }
  await withStore('sessions', 'readwrite', (s) => {
    s.clear();
    backup.sessions.forEach((row) => row && row.date && s.put(row));
  });
  if (Array.isArray(backup.events)) {
    await withStore('events', 'readwrite', (s) => {
      s.clear();
      backup.events.forEach(({ id, ...row }) => row && row.type && s.add(row));
    });
  }
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
        old.forEach((row) => row && row.date && s.put(row));
      });
      await logEvent('migrated_from_localstorage', { sessions: old.length });
    }
    localStorage.setItem('coach:migrated-idb', '1');
  } catch (e) {
    console.warn('[COACH] migration failed', e);
  }
}
