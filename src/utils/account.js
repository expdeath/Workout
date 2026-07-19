// ── Accounts via invite codes ────────────────────────────────────
// There is no signup. An account is provisioned by the owner (a
// private data repo + a fine-grained PAT scoped to it, optionally a
// Gemini key) and handed out as one base64url invite code made by
// scripts/make-invite.js. Redeeming a code just fills the same
// localStorage keys the app has always used — sync and the AI need
// no changes. Revocation = revoking that PAT on GitHub.

import { setApiKey, getApiKey } from './storage.js';
import { setSyncConfig, getSyncConfig } from '../db/sync.js';

const ACCOUNT_KEY = 'coach:account';

export function getAccount() {
  try {
    return JSON.parse(localStorage.getItem(ACCOUNT_KEY)) || null;
  } catch {
    return null;
  }
}

/** True on a fresh install with no account and no hand-entered setup
 *  (pre-account installs keep working without ever seeing Login). */
export function needsLogin() {
  return !getAccount() && !getApiKey() && !getSyncConfig().token;
}

function b64urlDecode(str) {
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

/** Decode + validate an invite code. Throws a user-readable error. */
export function parseInviteCode(code) {
  const raw = String(code || '').replace(/\s+/g, '');
  if (!raw) throw new Error('Paste the invite code you were sent.');
  let acct;
  try {
    acct = JSON.parse(b64urlDecode(raw));
  } catch {
    throw new Error("That doesn't look like a COACH invite code — check you copied all of it.");
  }
  if (!acct?.name || !acct?.repo || !acct?.ghToken) {
    throw new Error('Invite code is incomplete — ask for a new one.');
  }
  return acct;
}

/** Redeem: write the config the rest of the app already reads. */
export function applyAccount(acct) {
  setSyncConfig({ token: acct.ghToken, repo: acct.repo });
  if (acct.geminiKey) setApiKey(acct.geminiKey);
  localStorage.setItem(
    ACCOUNT_KEY,
    JSON.stringify({ name: acct.name, since: new Date().toISOString() })
  );
}

/** Clear every coach:* key and the local DB (cloud copies untouched). */
export async function wipeLocal() {
  for (const k of Object.keys(localStorage)) {
    if (k.startsWith('coach:')) localStorage.removeItem(k);
  }
  await new Promise((resolve) => {
    const req = indexedDB.deleteDatabase('coach-db');
    req.onsuccess = req.onerror = req.onblocked = () => resolve();
  });
}

/** Wipe this device back to the login screen (data stays in the cloud). */
export async function signOut() {
  await wipeLocal();
  window.location.reload();
}
