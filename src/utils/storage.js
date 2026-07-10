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
