// ── GitHub backup + Watch inbox ──────────────────────────────────
// Firestore (cloud.js) is the live database and syncs devices on its
// own. GitHub keeps two jobs:
//   1. Backup: the full account, as coach-backup.json (same shape as
//      always) + a human-readable README log, in the account's private
//      data repo. Pushed when data changed (≥10 min apart) or daily.
//   2. Watch inbox: the Gym Check-in Shortcut still PUTs files into
//      health-inbox/; every sync drains them into Firestore.
// The repo + a fine-grained token (Contents read/write on that repo
// only) live in accounts/{id}.github, so any device of the account
// can do both.

import { exportAll, mergeHealth } from './db.js';
import { cloudAccountDoc, cloudUpdateGithub, cloudSendFeedback, cloudSessions, cloudDeletedIds, currentAccount } from './cloud.js';
import { normalizeBackup, mergeBackups } from './backupShape.js';
import { sessionVolume, weekStats, parseHealthNumbers } from '../utils/stats.js';
import { setLogged, fmtDate, todayStr } from '../utils/helpers.js';
import { storeTodaysHealth } from '../utils/healthIngest.js';

export { normalizeBackup, mergeBackups };

const API = 'https://api.github.com';
const FILE = 'coach-backup.json';
const README = 'README.md';
const BRANCH = 'main';
const INBOX = 'health-inbox';
const MIN_GAP_MS = 10 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

// ── Config (accounts/{id}.github) ────────────────────────────────

export function getSyncConfig() {
  const g = cloudAccountDoc().github || {};
  return { token: g.token || '', repo: g.repo || '' };
}

export function setSyncConfig({ token, repo }) {
  return cloudUpdateGithub({
    token: token.trim(),
    repo: repo.trim().replace(/^https:\/\/github\.com\//, '').replace(/\/$/, ''),
  });
}

/** Last backup attempt, shared by every device of the account. */
export function getLastSync() {
  return cloudAccountDoc().github?.lastBackup || null;
}

function setLastSync(info) {
  return cloudUpdateGithub({ lastBackup: { ...(getLastSync() || {}), at: new Date().toISOString(), ...info } });
}

// ── GitHub API helpers ───────────────────────────────────────────

function gh(cfg, path, opts = {}) {
  return fetch(`${API}${path}`, {
    // GitHub's API sends max-age=60; a cached read here means a device
    // can miss another device's push for a minute and then fail its own
    // push with a version conflict. Always hit the network.
    cache: 'no-store',
    ...opts,
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      ...opts.headers,
    },
  });
}

// Unicode-safe base64 (browser + node)
function b64encode(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(bin);
}

/** Blob shas of our files on the remote ({ backup, readme }), or nulls. */
async function remoteShas(cfg) {
  const res = await gh(cfg, `/repos/${cfg.repo}/git/trees/${BRANCH}`);
  if (res.status === 404 || res.status === 409) return { backup: null, readme: null };
  if (!res.ok) throw new Error(`GitHub error ${res.status} reading repo tree`);
  const tree = await res.json();
  const shaOf = (p) => tree.tree?.find((t) => t.path === p)?.sha ?? null;
  return { backup: shaOf(FILE), readme: shaOf(README) };
}

async function pushFile(cfg, path, content, message, sha) {
  return gh(cfg, `/repos/${cfg.repo}/contents/${path}`, {
    method: 'PUT',
    body: JSON.stringify({
      message,
      content: b64encode(content),
      branch: BRANCH,
      ...(sha ? { sha } : {}),
    }),
  });
}

function commitMessage(backup) {
  const active = (backup.sessions || []).filter((s) => !s.deleted);
  const last = active[active.length - 1];
  return last
    ? `sync: ${active.length} sessions · latest ${last.date} ${last.plan?.sessionType || ''}`.trim()
    : 'sync: no sessions yet';
}

/** Overwrite coach-backup.json — Firestore is the truth, so no merge.
 *  A sha race with another device of the account just retries. */
async function pushRemote(cfg, backup) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const { backup: sha } = await remoteShas(cfg);
    // pretty-printed: GitHub renders it readably and diffs stay small
    const res = await pushFile(cfg, FILE, JSON.stringify(backup, null, 2), commitMessage(backup), sha);
    if (res.ok) return;
    if (res.status === 401 || res.status === 403) {
      throw new Error('GitHub token rejected — check it in Settings (needs Contents read/write on your data repo).');
    }
    if (res.status !== 409 && res.status !== 422) throw new Error(`GitHub error ${res.status} pushing backup`);
    await new Promise((r) => setTimeout(r, 800));
  }
  throw new Error('Backup conflict — another device is backing up right now. It will retry later.');
}

// ── Repo README: human-readable training log for GitHub ─────────

export function buildReadme(sessions) {
  const active = (sessions || []).filter((s) => !s.deleted && s.date);
  const { thisWeek, streak } = weekStats(active);
  const rows = active
    .slice(-20)
    .reverse()
    .map((s) => {
      const vol = sessionVolume(s);
      const best = (s.plan?.exercises || [])
        .map((ex, i) => {
          const sets = (s.log?.[i] || []).filter(setLogged);
          if (!sets.length) return null;
          const top = sets.reduce((a, b) =>
            (parseFloat(b.weight) || 0) > (parseFloat(a.weight) || 0) ? b : a
          );
          return `${ex.name} ${top.weight || '?'}×${top.reps || '?'}`;
        })
        .filter(Boolean)
        .join(' · ');
      return `| ${fmtDate(s.date)} | ${s.plan?.sessionType || '?'} | ${s.fin?.rpe ?? '—'} | ${vol ? vol.toLocaleString() + ' kg' : '—'} | ${best || '—'} |`;
    })
    .join('\n');

  return `# 🏋️ COACH — Training Data

Auto-synced by the [COACH app](https://expdeath.github.io/Workout/). Don't edit by hand — the app owns this repo.

**${active.length} sessions** · **${thisWeek} this week** · **${streak}-week streak** (≥3/week)

## Recent sessions

| Date | Session | RPE | Volume | Top sets |
|---|---|---|---|---|
${rows || '| — | — | — | — | — |'}

<sub>Full data (including the event log) lives in [\`coach-backup.json\`](./coach-backup.json). Updated ${new Date().toISOString().slice(0, 16).replace('T', ' ')} UTC.</sub>
`;
}

async function pushReadme(cfg, sessions) {
  try {
    const { readme } = await remoteShas(cfg);
    const res = await pushFile(cfg, README, buildReadme(sessions), 'docs: update training log', readme);
    if (!res.ok) console.warn('[COACH] README update skipped', res.status);
  } catch (e) {
    console.warn('[COACH] README update failed', e); // cosmetic — never fatal
  }
}

// ── Beta feedback ────────────────────────────────────────────────
// Stored under accounts/{id}/feedback — the owner reads it in the
// Firebase console (Firestore → accounts → … → feedback).

export async function sendFeedback(text) {
  const body = String(text || '').trim();
  if (!body) throw new Error('Write something first.');
  try {
    await cloudSendFeedback(body.slice(0, 2000));
  } catch {
    throw new Error("Couldn't send — check your connection and try again.");
  }
}

// ── Health inbox ─────────────────────────────────────────────────
// The Watch shortcut PUTs one small file per run into health-inbox/
// (background HTTP — no browser hop, works with the phone locked).
// Every sync drains the inbox: parse → merge into the health store →
// delete the file. Filenames carry the date; always-unique names mean
// the shortcut never needs a sha and can never conflict.

/** File body → { text } or { text, nums }. Accepts plain text,
 *  {"health":"…"}, or {"hrv":48,"rhr":57,"sleepH":7.5,…}. */
function parseInboxFile(body) {
  const t = String(body || '').trim();
  if (t.startsWith('{')) {
    try {
      const o = JSON.parse(t);
      if (typeof o.health === 'string') return { text: o.health };
      const nums = {};
      for (const k of ['hrv', 'rhr', 'steps', 'sleepH', 'weightKg']) {
        if (typeof o[k] === 'number' && o[k] > 0) nums[k] = o[k];
      }
      if (Object.keys(nums).length) return { text: t, nums };
    } catch { /* not JSON — treat as plain text */ }
  }
  return { text: t };
}

export function getLastInbox() {
  try {
    return JSON.parse(localStorage.getItem('coach:last-inbox')) || null;
  } catch {
    return null;
  }
}

/**
 * Drain health-inbox/: merge every file into the local health store,
 * pre-fill today's check-in when a file is from today, then delete the
 * file from the repo. Per-file failures are skipped (retried next
 * sync). Returns the number of files ingested.
 */
export async function consumeHealthInbox(cfg = getSyncConfig()) {
  if (!cfg.token || !cfg.repo) return 0;
  const res = await gh(cfg, `/repos/${cfg.repo}/contents/${INBOX}?ref=${BRANCH}`);
  if (res.status === 404) return 0; // no inbox folder yet — nothing delivered
  if (!res.ok) throw new Error(`GitHub error ${res.status} listing health inbox`);
  const files = await res.json();
  if (!Array.isArray(files)) return 0;
  let ingested = 0;
  for (const f of files.filter((x) => x?.type === 'file').slice(0, 30)) {
    try {
      const raw = await gh(
        cfg,
        `/repos/${cfg.repo}/contents/${INBOX}/${encodeURIComponent(f.name)}?ref=${BRANCH}`,
        { headers: { Accept: 'application/vnd.github.raw+json' } }
      );
      if (!raw.ok) continue;
      const { text, nums } = parseInboxFile(await raw.text());
      const date = /(\d{4}-\d{2}-\d{2})/.exec(f.name)?.[1] || todayStr();
      // readable form pre-fills the check-in and is what the AI reads
      const asText = nums
        ? [
            nums.hrv && `HRV ${nums.hrv} ms`,
            nums.rhr && `RHR ${nums.rhr}`,
            nums.sleepH && `Sleep ${nums.sleepH}h`,
            nums.weightKg && `Weight ${nums.weightKg}kg`,
            nums.steps && `Steps ${nums.steps}`,
          ]
            .filter(Boolean)
            .join(' · ')
        : text;
      if (!asText) continue;
      if (date === todayStr()) {
        storeTodaysHealth(asText); // localStorage prefill + health-store row
      } else {
        const n = parseHealthNumbers(asText);
        await mergeHealth({
          date,
          hrv: n.hrv || null,
          rhr: n.rhr || null,
          steps: n.steps || null,
          sleepH: n.sleepH || null,
          raw: asText.slice(0, 300),
        });
      }
      // structured payloads may carry fields the text parser doesn't (weightKg)
      if (nums) await mergeHealth({ date, ...nums });
      const del = await gh(
        cfg,
        `/repos/${cfg.repo}/contents/${INBOX}/${encodeURIComponent(f.name)}`,
        {
          method: 'DELETE',
          body: JSON.stringify({ message: `chore: ingest ${f.name}`, sha: f.sha, branch: BRANCH }),
        }
      );
      if (!del.ok) console.warn('[COACH] inbox delete failed', f.name, del.status);
      ingested++;
    } catch (e) {
      console.warn('[COACH] inbox file failed', f?.name, e);
    }
  }
  if (ingested) {
    localStorage.setItem(
      'coach:last-inbox',
      JSON.stringify({ at: Date.now(), files: ingested })
    );
  }
  return ingested;
}

// ── Sync ─────────────────────────────────────────────────────────

/** Cheap "did anything change since the last backup" check. */
function fingerprint() {
  const sessions = cloudSessions();
  const newest = Math.max(0, ...sessions.map((s) => s.updatedAt || 0));
  return `${sessions.length}:${newest}:${cloudDeletedIds().length}`;
}

/**
 * Drain the Watch inbox into Firestore, then back the account up to
 * GitHub if it's due. `replaceRemote` (or `force`) backs up now.
 * Returns { status, changedLocal, sessions, inboxFiles }.
 */
export async function syncNow({ replaceRemote = false, force = false } = {}) {
  const cfg = getSyncConfig();
  const sessions = cloudSessions().length;
  if (!currentAccount() || !cfg.token || !cfg.repo) {
    return { status: 'unconfigured', changedLocal: false, sessions };
  }

  // never fatal — a broken inbox must not block the backup
  let inboxFiles = 0;
  try {
    inboxFiles = await consumeHealthInbox(cfg);
  } catch (e) {
    console.warn('[COACH] health inbox check failed', e);
  }

  const last = getLastSync();
  const lastAt = last?.at ? Date.parse(last.at) : 0;
  const fp = fingerprint();
  const due =
    replaceRemote ||
    force ||
    last?.status !== 'ok' ||
    Date.now() - lastAt > DAY_MS ||
    (fp !== last?.fingerprint && Date.now() - lastAt > MIN_GAP_MS);
  if (!due) return { status: 'ok', changedLocal: inboxFiles > 0, sessions, inboxFiles, skipped: true };

  try {
    const backup = normalizeBackup(await exportAll());
    await pushRemote(cfg, backup);
    await pushReadme(cfg, backup.sessions);
    await setLastSync({ status: 'ok', sessions: backup.sessions.length, fingerprint: fp, message: null });
    return { status: 'ok', changedLocal: inboxFiles > 0, sessions: backup.sessions.length, inboxFiles };
  } catch (e) {
    await setLastSync({ status: 'error', message: e.message });
    throw e;
  }
}
