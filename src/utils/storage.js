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
  cloudProActive,
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

/** Can the AI coach run at all? A key (own or shared), or COACH Pro. */
export const aiReady = () => !!getApiKey() || cloudProActive();

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

// ── Preferences (Settings → Alerts & reports) ──
// All on by default — that's how the app behaved before they existed.
const PREF_DEFAULTS = {
  restSound: true, // beep when the rest timer ends
  restVibrate: true, // …and buzz
  restNotify: true, // …and notify when the app is in the background
  keepAwake: true, // screen stays on during a workout
  weeklyReview: true, // Sunday AI review
  monthlyReport: true, // new-month AI report
  debrief: true, // two-sentence AI debrief after each session
};

export function getPrefs() {
  return { ...PREF_DEFAULTS, ...(cloudState('prefs', {}) || {}) };
}

export function setPref(key, value) {
  cloudSetState('prefs', { ...(cloudState('prefs', {}) || {}), [key]: value });
}

// ── AI consent: may the app send data to Google Gemini? ──
// Account state `aiConsent` { allowed, at, version } — asked once per
// account (screens/AIConsent.jsx), changeable in Settings → AI Coach.
export const AI_CONSENT_VERSION = 1;

/** null = never asked; otherwise { allowed, at, version }. */
export function getAIConsent() {
  return cloudState('aiConsent', null);
}

export const hasAIConsent = () => getAIConsent()?.allowed === true;

export function setAIConsent(allowed) {
  cloudSetState('aiConsent', { allowed: !!allowed, at: Date.now(), version: AI_CONSENT_VERSION });
}
