// ── Cloud Firestore: the live database ───────────────────────────
// Every device signs in with Google; the allowlist maps the email to
// one account, and that account's documents (schema: docs/firestore.md)
// are mirrored into memory here and kept live with snapshot listeners.
// The rest of the app reads that mirror synchronously (db.js,
// storage.js, healthIngest.js keep their old function names) and
// writes through it: the mirror updates at once, the Firestore write
// runs in the background — queued in the offline cache when there's
// no signal, so logging a set never waits on the network.

import { initializeApp } from 'firebase/app';
import {
  getAuth,
  onAuthStateChanged,
  GoogleAuthProvider,
  signInWithPopup,
  signInWithRedirect,
  getRedirectResult,
  signOut as fbSignOut,
} from 'firebase/auth';
import {
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
  doc,
  collection,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  onSnapshot,
  writeBatch,
  getCountFromServer,
  terminate,
  clearIndexedDbPersistence,
} from 'firebase/firestore';
import { encodeValue, decodeValue, docId, eventDocId } from './firestoreCodec.js';

// Public by design — access is enforced by firestore.rules + the allowlist.
const firebaseConfig = {
  apiKey: 'AIzaSyDE2zTvTacbQn2vgSTDY0LvHB-Gr7xAhec',
  authDomain: 'heath-9a322.firebaseapp.com',
  projectId: 'heath-9a322',
  storageBucket: 'heath-9a322.firebasestorage.app',
  messagingSenderId: '204447158862',
  appId: '1:204447158862:web:5c8b43f5e9e902f19e291f',
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = initializeFirestore(app, {
  ignoreUndefinedProperties: true,
  // browsers keep an offline copy (IndexedDB); node (tests) stays in memory
  ...(typeof indexedDB !== 'undefined'
    ? { localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }) }
    : {}),
});

// ── Mirror ───────────────────────────────────────────────────────

const empty = () => ({
  sessions: new Map(), // id → session
  health: new Map(), // date → row
  deletedIds: new Map(), // id → at
  state: new Map(), // key → value (decoded)
  account: null, // accounts/{id} doc
  shared: {}, // config/shared
});

let mirror = empty();
let current = null; // { accountId, name, admin, email, uid }
let unsubs = [];
const listeners = new Set();

/** Called with a reason string whenever the mirror changes. */
export function onCloudChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
const notify = (why) => listeners.forEach((fn) => { try { fn(why); } catch (e) { console.warn(e); } });

export const currentAccount = () => current;
const acctPath = (...p) => ['accounts', current.accountId, ...p].join('/');

/** Background write: failures are logged (and reverted by the next
 *  snapshot), never thrown into the UI. Returns the promise for tests. */
function bg(promise, what) {
  return promise.catch((e) => console.warn(`[COACH] cloud write failed (${what})`, e));
}

export class NotInvitedError extends Error {
  constructor(email) {
    super(`${email} isn't on the COACH invite list. Ask Abhi to add it.`);
    this.email = email;
  }
}

/**
 * Bind the mirror to the signed-in user's account. Resolves once every
 * listener has delivered its first snapshot (from the offline cache
 * when there's no network), so the app can render real data at once.
 */
export async function startSession(user) {
  stopSession();
  const email = (user.email || '').toLowerCase();
  const entrySnap = await getDoc(doc(db, 'allowlist', email)).catch(() => null);
  if (!entrySnap?.exists()) throw new NotInvitedError(email);
  const entry = entrySnap.data();
  current = { accountId: entry.accountId, name: entry.name || '', admin: !!entry.admin, email, uid: user.uid };
  mirror = empty();

  const firsts = [];
  const watch = (ref, apply, label) => {
    let resolve;
    firsts.push(new Promise((r) => (resolve = r)));
    const isDoc = ref.type === 'document';
    unsubs.push(
      onSnapshot(
        ref,
        (snap) => {
          if (isDoc) apply(snap);
          else snap.docChanges().forEach((ch) => apply(ch));
          resolve();
          notify(label);
        },
        (err) => {
          console.warn(`[COACH] listener ${label} failed`, err);
          resolve();
        }
      )
    );
  };
  const col = (name) => collection(db, acctPath(name));

  watch(doc(db, acctPath()), (s) => { mirror.account = s.exists() ? s.data() : null; }, 'account');
  watch(doc(db, 'config/shared'), (s) => { mirror.shared = s.exists() ? s.data() : {}; }, 'shared');
  watch(col('sessions'), (ch) => {
    const v = decodeValue(ch.doc.data());
    if (ch.type === 'removed') mirror.sessions.delete(v.id || ch.doc.id);
    else mirror.sessions.set(v.id || ch.doc.id, v);
  }, 'sessions');
  watch(col('health'), (ch) => {
    const v = decodeValue(ch.doc.data());
    if (ch.type === 'removed') mirror.health.delete(v.date);
    else mirror.health.set(v.date, v);
  }, 'health');
  watch(col('deletedIds'), (ch) => {
    const v = ch.doc.data();
    if (ch.type === 'removed') mirror.deletedIds.delete(v.id);
    else mirror.deletedIds.set(v.id, v.at || 0);
  }, 'deletedIds');
  watch(col('state'), (ch) => {
    const key = ch.doc.id;
    if (ch.type === 'removed') return void mirror.state.delete(key);
    const data = ch.doc.data();
    // aiSettings is stored as the object itself; every other key wraps it
    mirror.state.set(key, key === 'aiSettings' ? decodeValue(data) : decodeValue(data.value));
  }, 'state');

  await Promise.all(firsts);
  return current;
}

export function stopSession() {
  unsubs.forEach((u) => u());
  unsubs = [];
  current = null;
  mirror = empty();
}

// ── Reads (synchronous, from the mirror) ─────────────────────────

export const cloudSessions = () => [...mirror.sessions.values()];
export const cloudHealth = () => [...mirror.health.values()];
export const cloudDeletedIds = () => [...mirror.deletedIds].map(([id, at]) => ({ id, at }));
export const cloudState = (key, fallback = null) => (mirror.state.has(key) ? mirror.state.get(key) : fallback);
export const cloudStateKeys = () => [...mirror.state.keys()];
export const cloudAccountDoc = () => mirror.account || {};
export const cloudShared = () => mirror.shared || {};

// ── Writes (mirror now, Firestore in the background) ─────────────

export function cloudPutSession(session) {
  if (!current) return Promise.resolve();
  mirror.sessions.set(session.id, session);
  notify('sessions');
  return bg(setDoc(doc(db, acctPath('sessions', docId(session.id))), encodeValue(session)), 'session');
}

/** Delete for real + permanent marker, atomically. */
export function cloudDeleteSession(id, at = Date.now()) {
  if (!current) return Promise.resolve();
  mirror.sessions.delete(id);
  mirror.deletedIds.set(id, at);
  notify('sessions');
  const b = writeBatch(db);
  b.set(doc(db, acctPath('deletedIds', docId(id))), { id, at });
  b.delete(doc(db, acctPath('sessions', docId(id))));
  return bg(b.commit(), 'delete session');
}

export function cloudPutHealth(row) {
  if (!current || !row?.date) return Promise.resolve();
  mirror.health.set(row.date, row);
  notify('health');
  return bg(setDoc(doc(db, acctPath('health', docId(row.date))), encodeValue(row)), 'health');
}

export function cloudSetState(key, value) {
  if (!current) return Promise.resolve();
  const ref = doc(db, acctPath('state', docId(key)));
  if (value === null || value === undefined) {
    mirror.state.delete(key);
    notify('state');
    return bg(deleteDoc(ref), `state ${key}`);
  }
  mirror.state.set(key, value);
  notify('state');
  const data = key === 'aiSettings' ? encodeValue(value) : { value: encodeValue(value), updatedAt: Date.now() };
  return bg(setDoc(ref, data), `state ${key}`);
}

export function cloudLogEvent(event) {
  if (!current) return Promise.resolve();
  return bg(setDoc(doc(db, acctPath('events', eventDocId(event))), encodeValue(event)), 'event');
}

/** Patch accounts/{id}.github ({ repo, token, lastBackup… }). */
export function cloudUpdateGithub(patch) {
  if (!current) return Promise.resolve();
  const github = { ...(mirror.account?.github || {}), ...patch };
  mirror.account = { ...(mirror.account || {}), github };
  notify('account');
  return bg(updateDoc(doc(db, acctPath()), { github }), 'github settings');
}

/** Owner only (rules enforce it): the shared Gemini key. */
export function cloudSetSharedKey(geminiKey) {
  mirror.shared = { ...mirror.shared, geminiKey };
  notify('shared');
  return bg(setDoc(doc(db, 'config/shared'), { geminiKey }, { merge: true }), 'shared key');
}

export function cloudSendFeedback(text) {
  const ref = doc(collection(db, acctPath('feedback')));
  // awaited: the user is told it was sent
  return setDoc(ref, { text, name: current?.name || '', email: current?.email || '', at: Date.now() });
}

// ── Whole-collection operations (export / import / clear) ───────

/** All events, fetched on demand (they're write-only otherwise). */
export async function cloudAllEvents() {
  if (!current) return [];
  const qs = await getDocs(collection(db, acctPath('events')));
  return qs.docs.map((d) => decodeValue(d.data()));
}

export async function cloudCountEvents() {
  if (!current) return 0;
  try {
    return (await getCountFromServer(collection(db, acctPath('events')))).data().count;
  } catch {
    return 0;
  }
}

/** Batched writes, ≤450 ops per batch (Firestore caps at 500). */
async function inBatches(ops) {
  for (let i = 0; i < ops.length; i += 450) {
    const b = writeBatch(db);
    for (const op of ops.slice(i, i + 450)) op(b);
    await b.commit();
  }
}

/**
 * Make the account's sessions/health/deletedIds/events exactly match
 * `backup` (already normalized). Used by "Import backup". Awaited.
 */
export async function cloudReplaceData(backup) {
  if (!current) return;
  const ops = [];
  const keep = (map, key) => new Set(backup[key].map(map));
  const sessionIds = keep((s) => s.id, 'sessions');
  for (const id of mirror.sessions.keys()) {
    if (!sessionIds.has(id)) ops.push((b) => b.delete(doc(db, acctPath('sessions', docId(id)))));
  }
  const dates = keep((h) => h.date, 'health');
  for (const d of mirror.health.keys()) {
    if (!dates.has(d)) ops.push((b) => b.delete(doc(db, acctPath('health', docId(d)))));
  }
  // deletion markers are permanent — import only ever adds to them
  for (const d of backup.deletedIds) ops.push((b) => b.set(doc(db, acctPath('deletedIds', docId(d.id))), d));
  // the rules refuse older copies and deleted ids (newer wins, deletion
  // wins), and one refused write fails its whole batch — skip them here
  const deleted = new Set([...mirror.deletedIds.keys(), ...backup.deletedIds.map((d) => d.id)]);
  let skipped = 0;
  for (const s of backup.sessions) {
    const cur = mirror.sessions.get(s.id);
    if (deleted.has(s.id) || (cur && (cur.updatedAt || 0) > (s.updatedAt || 0))) {
      skipped++;
      continue;
    }
    ops.push((b) => b.set(doc(db, acctPath('sessions', docId(s.id))), encodeValue(s)));
  }
  for (const h of backup.health) ops.push((b) => b.set(doc(db, acctPath('health', docId(h.date))), encodeValue(h)));
  for (const e of backup.events) ops.push((b) => b.set(doc(db, acctPath('events', eventDocId(e))), encodeValue(e)));
  await inBatches(ops);
  return { skipped };
}

/** "Clear all history": every session removed AND marked deleted, so
 *  no device that was offline can bring them back. */
export async function cloudClearSessions() {
  if (!current) return;
  const now = Date.now();
  const ids = [...mirror.sessions.keys()];
  for (const id of ids) {
    mirror.sessions.delete(id);
    mirror.deletedIds.set(id, now);
  }
  notify('sessions');
  await inBatches(
    ids.flatMap((id) => [
      (b) => b.set(doc(db, acctPath('deletedIds', docId(id))), { id, at: now }),
      (b) => b.delete(doc(db, acctPath('sessions', docId(id)))),
    ])
  );
}

// ── Auth ─────────────────────────────────────────────────────────

/** Resolves with the signed-in Firebase user, or null — once. */
export function currentUser() {
  return new Promise((resolve) => {
    const off = onAuthStateChanged(auth, (u) => {
      off();
      resolve(u);
    });
  });
}

export async function signInWithGoogle() {
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });
  try {
    return (await signInWithPopup(auth, provider)).user;
  } catch (e) {
    // home-screen apps / strict browsers can block the popup — fall back
    if (['auth/popup-blocked', 'auth/operation-not-supported-in-this-environment'].includes(e.code)) {
      await signInWithRedirect(auth, provider);
      return null; // page navigates away
    }
    throw e;
  }
}

/** Finishes a redirect sign-in on the page load after it (no-op otherwise). */
export const finishRedirectSignIn = () => getRedirectResult(auth).catch(() => null);

/** Sign out and drop this device's offline copy of the account. */
export async function cloudSignOut() {
  stopSession();
  await fbSignOut(auth).catch(() => {});
  try {
    await terminate(db);
    await clearIndexedDbPersistence(db);
  } catch { /* already cleared / not persistent */ }
}
