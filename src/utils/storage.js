// ── Settings & small state ───────────────────────────────────────
// Backed by the signed-in account in Firestore (src/db/cloud.js), so
// every device sees the same values. Synchronous getters read the
// in-memory mirror; setters update it at once and save in the background.

import { cloudState, cloudSetState, cloudShared, cloudSetSharedKey, currentAccount } from '../db/cloud.js';

export async function loadKey(key, fallback) {
  return cloudState(key, fallback);
}

export async function saveKey(key, value) {
  await cloudSetState(key, value);
}

// ── Gemini key: one shared key for every account (config/shared) ──

export function getApiKey() {
  return cloudShared().geminiKey || '';
}

/** Owner only — firestore.rules reject anyone else's write. */
export function setApiKey(key) {
  if (!currentAccount()?.admin) return;
  if (key === getApiKey()) return;
  cloudSetSharedKey(key);
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
