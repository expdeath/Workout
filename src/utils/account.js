// ── Accounts: Google sign-in + an owner-managed allowlist ─────────
// There is no signup. The owner adds a person's Google email to the
// Firestore allowlist (allowlist/{email} → accountId); signing in with
// that Google account opens their account on any device. Revoking =
// deleting the allowlist entry.

import {
  currentUser,
  startSession,
  currentAccount,
  cloudSignOut,
  cloudAccountDoc,
  cloudUpdateGithub,
  cloudShared,
  cloudSetSharedKey,
  cloudState,
  cloudSetState,
  finishRedirectSignIn,
} from '../db/cloud.js';

/** { name, accountId, admin, email } of the signed-in account, or null. */
export function getAccount() {
  return currentAccount();
}

/**
 * Boot: resolve the signed-in Google user and open their account.
 * Returns the account, or null when nobody is signed in. Throws
 * NotInvitedError (from cloud.js) for an email not on the allowlist.
 */
export async function resumeSession() {
  await finishRedirectSignIn();
  const user = await currentUser();
  if (!user) return null;
  const acct = await startSession(user);
  adoptLegacyBrowserData();
  return acct;
}

/**
 * One-time handover from the pre-Firestore app on this browser: its
 * Gemini key (owner only → the shared key), its GitHub token (when it
 * belongs to this account's repo), and the browser-only state that was
 * never synced (in-progress workout, cached reports, today's chat).
 * Only fills what the cloud doesn't already have; never overwrites.
 */
function adoptLegacyBrowserData() {
  try {
    const acct = currentAccount();
    const ls = (k) => localStorage.getItem(k);
    const json = (k) => {
      try {
        return JSON.parse(ls(k));
      } catch {
        return null;
      }
    };

    const key = ls('coach:gemini-api-key');
    if (acct.admin && key && !cloudShared().geminiKey) cloudSetSharedKey(key);

    const gh = cloudAccountDoc().github || {};
    const token = ls('coach:gh-token');
    const repo = (ls('coach:gh-repo') || '').toLowerCase();
    if (token && !gh.token && gh.repo && repo === gh.repo.toLowerCase()) {
      cloudUpdateGithub({ token });
    }

    const carry = [
      ['coach:today', 'today'],
      ['coach:weekly-review', 'weeklyReview'],
      ['coach:monthly-report', 'monthlyReport'],
    ];
    for (const k of Object.keys(localStorage)) {
      const m = /^coach:chat-(\d{4}-\d{2}-\d{2})$/.exec(k);
      if (m) carry.push([k, `chat-${m[1]}`]);
    }
    for (const [from, to] of carry) {
      const v = json(from);
      if (v && cloudState(to, null) === null) cloudSetState(to, v);
    }
  } catch (e) {
    console.warn('[COACH] legacy handover skipped', e);
  }
}

/** Clear every coach:* key and the local media DB (cloud copies untouched). */
export async function wipeLocal() {
  for (const k of Object.keys(localStorage)) {
    if (k.startsWith('coach:')) localStorage.removeItem(k);
  }
  await new Promise((resolve) => {
    const req = indexedDB.deleteDatabase('coach-db');
    req.onsuccess = req.onerror = req.onblocked = () => resolve();
  });
}

/** Sign out: this device forgets the account (data stays in the cloud). */
export async function signOut() {
  await cloudSignOut();
  await wipeLocal();
  window.location.reload();
}
