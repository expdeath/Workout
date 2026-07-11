// ── Storage helpers ──────────────────────────────────────────────
// localStorage-based persistence. Mirrors the old window.storage
// interface so the rest of the app doesn't change.

const PREFIX = 'coach:';

export async function loadKey(key, fallback) {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    return raw !== null ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

export async function saveKey(key, value) {
  try {
    localStorage.setItem(PREFIX + key, JSON.stringify(value));
  } catch (e) {
    console.error('storage save failed', e);
  }
}

export function getApiKey() {
  return localStorage.getItem('coach:gemini-api-key') || '';
}

export function setApiKey(key) {
  localStorage.setItem('coach:gemini-api-key', key);
}

// ── AI coach setup (personal profile + base routine) ─────────────
// Kept out of the public app code for privacy; travels with the
// cloud backup (newest edit wins across devices).

export function getAISettings() {
  try {
    return JSON.parse(localStorage.getItem('coach:ai-settings')) || {};
  } catch {
    return {};
  }
}

export function setAISettings(patch) {
  const cur = getAISettings();
  localStorage.setItem(
    'coach:ai-settings',
    JSON.stringify({ ...cur, ...patch, updatedAt: Date.now() })
  );
}

/** Raw restore (backup import / sync) — preserves updatedAt. */
export function restoreAISettings(obj) {
  if (obj && typeof obj === 'object') {
    localStorage.setItem('coach:ai-settings', JSON.stringify(obj));
  }
}
