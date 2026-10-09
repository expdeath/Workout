// ── Settings & small state ───────────────────────────────────────
// Backed by the signed-in account in Firestore (src/db/cloud.js), so
// every device sees the same values. Synchronous getters read the
// in-memory mirror; setters update it at once and save in the background.

import {
  cloudState,
  cloudSetState,
  cloudShared,
  cloudSetSharedKey,
  cloudAccountDoc,
  cloudSetOwnKey,
  currentAccount,
} from '../db/cloud.js';

export async function loadKey(key, fallback) {
  return cloudState(key, fallback);
}

export async function saveKey(key, value) {
  await cloudSetState(key, value);
}

// ── Gemini key: invited accounts share the owner's (config/shared);
//    self-serve accounts bring their own (accounts/{id}.geminiKey) ──

export function getApiKey() {
  return (currentAccount()?.selfServe ? cloudAccountDoc().geminiKey : cloudShared().geminiKey) || '';
}

/** Can this account change its key? The owner (shared) or a self-serve account (own). */
export const canSetApiKey = () => !!(currentAccount()?.admin || currentAccount()?.selfServe);

export function setApiKey(key) {
  if (!canSetApiKey() || key === getApiKey()) return;
  if (currentAccount().selfServe) cloudSetOwnKey(key);
  else cloudSetSharedKey(key);
}

// ── AI coach setup (personal profile + base routine + gym setup) ──
// Newest edit wins across devices (updatedAt, enforced by the rules).

export function getAISettings() {
  return cloudState('aiSettings', {}) || {};
}

export function setAISettings(patch) {
  cloudSetState('aiSettings', { ...getAISettings(), ...patch, updatedAt: Date.now() });
}

/** Raw restore (backup import) — preserves updatedAt. */
export function restoreAISettings(obj) {
  if (obj && typeof obj === 'object') cloudSetState('aiSettings', obj);
}
