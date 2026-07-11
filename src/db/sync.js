// ── Cloud sync via a private GitHub repo ─────────────────────────
// The full backup (sessions + event log) lives as one JSON file in
// a private repo the user owns. Sync = pull remote, merge with
// local (union; newer session wins per date), write both sides.
// Auth: a fine-grained PAT scoped to that single repo, stored in
// localStorage like the Gemini key. Only ever sent to api.github.com
// (enforced by the CSP).

import { exportAll, replaceAll, sessionId } from './db.js';
import { sessionVolume, weekStats } from '../utils/stats.js';
import { setLogged, fmtDate } from '../utils/helpers.js';

const API = 'https://api.github.com';
const FILE = 'coach-backup.json';
const README = 'README.md';
const BRANCH = 'main';

// ── Config ───────────────────────────────────────────────────────

export function getSyncConfig() {
  return {
    token: localStorage.getItem('coach:gh-token') || '',
    repo: localStorage.getItem('coach:gh-repo') || '',
  };
}

export function setSyncConfig({ token, repo }) {
  localStorage.setItem('coach:gh-token', token.trim());
  localStorage.setItem('coach:gh-repo', repo.trim().replace(/^https:\/\/github\.com\//, '').replace(/\/$/, ''));
}

export function getLastSync() {
  try {
    return JSON.parse(localStorage.getItem('coach:last-sync')) || null;
  } catch {
    return null;
  }
}

function setLastSync(info) {
  localStorage.setItem(
    'coach:last-sync',
    JSON.stringify({ at: new Date().toISOString(), ...info })
  );
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

/** Download + parse the remote backup. Raw media type dodges the 1MB JSON cap. */
async function fetchRemote(cfg) {
  const res = await gh(
    cfg,
    `/repos/${cfg.repo}/contents/${FILE}?ref=${BRANCH}`,
    { headers: { Accept: 'application/vnd.github.raw+json' } }
  );
  if (res.status === 404) return null;
  if (res.status === 401 || res.status === 403) {
    throw new Error('GitHub token rejected — check it in Settings (needs Contents read/write on your data repo).');
  }
  if (!res.ok) throw new Error(`GitHub error ${res.status} fetching backup`);
  try {
    return JSON.parse(await res.text());
  } catch {
    throw new Error('Remote backup file is not valid JSON.');
  }
}

function commitMessage(backup) {
  const active = (backup.sessions || []).filter((s) => !s.deleted);
  const last = active[active.length - 1];
  return last
    ? `sync: ${active.length} sessions · latest ${last.date} ${last.plan?.sessionType || ''}`.trim()
    : 'sync: no sessions yet';
}

async function pushRemote(cfg, backup, sha) {
  const res = await gh(cfg, `/repos/${cfg.repo}/contents/${FILE}`, {
    method: 'PUT',
    body: JSON.stringify({
      message: commitMessage(backup),
      // pretty-printed: GitHub renders it readably and diffs stay small
      content: b64encode(JSON.stringify(backup, null, 2)),
      branch: BRANCH,
      ...(sha ? { sha } : {}),
    }),
  });
  if (res.status === 409 || res.status === 422) {
    const err = new Error('sync conflict');
    err.conflict = true;
    throw err;
  }
  if (res.status === 401 || res.status === 403) {
    throw new Error('GitHub token rejected — check it in Settings (needs Contents read/write on your data repo).');
  }
  if (!res.ok) throw new Error(`GitHub error ${res.status} pushing backup`);
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

async function pushReadme(cfg, sessions, sha) {
  try {
    const res = await gh(cfg, `/repos/${cfg.repo}/contents/${README}`, {
      method: 'PUT',
      body: JSON.stringify({
        message: 'docs: update training log',
        content: b64encode(buildReadme(sessions)),
        branch: BRANCH,
        ...(sha ? { sha } : {}),
      }),
    });
    if (!res.ok) console.warn('[COACH] README update skipped', res.status);
  } catch (e) {
    console.warn('[COACH] README update failed', e); // cosmetic — never fatal
  }
}

// ── Merge ────────────────────────────────────────────────────────

function pickSession(local, remote) {
  if (!remote) return local;
  if (!local) return remote;
  const lu = local.updatedAt || 0;
  const ru = remote.updatedAt || 0;
  if (lu !== ru) return lu > ru ? local : remote;
  if (local.finished !== remote.finished) return local.finished ? local : remote;
  return local;
}

const eventKey = (e) => `${e.iso}|${e.type}`;

export function mergeBackups(local, remote) {
  if (!remote) return normalizeBackup(local);
  // union by session id (legacy rows: id = date) — same-day workouts
  // from different check-ins are distinct sessions and both survive
  const byId = new Map();
  for (const s of remote.sessions || []) if (s?.date) byId.set(sessionId(s), s);
  for (const s of local.sessions || []) {
    if (s?.date) byId.set(sessionId(s), pickSession(s, byId.get(sessionId(s))));
  }
  const seen = new Set();
  const events = [];
  for (const e of [...(local.events || []), ...(remote.events || [])]) {
    if (!e?.type || seen.has(eventKey(e))) continue;
    seen.add(eventKey(e));
    events.push(e);
  }
  return normalizeBackup({
    ...local,
    sessions: [...byId.values()],
    events,
  });
}

/** Deterministic shape so backups can be compared as JSON strings. */
export function normalizeBackup(b) {
  return {
    app: 'coach',
    version: b.version || 1,
    sessions: (b.sessions || [])
      .map((s) => ({ ...s, id: sessionId(s) }))
      .sort((a, x) => (a.date + a.id).localeCompare(x.date + x.id)),
    events: (b.events || [])
      .map(({ id, ...e }) => e)
      .sort((a, x) => (eventKey(a) < eventKey(x) ? -1 : 1)),
  };
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ── Sync ─────────────────────────────────────────────────────────

/**
 * Pull remote, merge with local, write back whichever side is stale.
 * With replaceRemote: overwrite the cloud with local state (used after
 * "Clear all history", where a merge would resurrect deleted data).
 * Returns { status, changedLocal }.
 */
export async function syncNow({ replaceRemote = false } = {}) {
  const cfg = getSyncConfig();
  if (!cfg.token || !cfg.repo) return { status: 'unconfigured', changedLocal: false };

  const local = normalizeBackup(await exportAll());

  if (replaceRemote) {
    const shas = await remoteShas(cfg);
    await pushRemote(cfg, local, shas.backup);
    await pushReadme(cfg, local.sessions, (await remoteShas(cfg)).readme);
    setLastSync({ status: 'ok', sessions: local.sessions.length });
    return { status: 'pushed', changedLocal: false, sessions: local.sessions.length };
  }

  const doPass = async () => {
    const remote = await fetchRemote(cfg);
    const remoteNorm = remote ? normalizeBackup(remote) : null;
    const merged = mergeBackups(local, remoteNorm);
    const changedLocal = !same(merged, local);
    if (changedLocal) await replaceAll(merged);
    if (!remote || !same(merged, remoteNorm)) {
      const shas = await remoteShas(cfg);
      await pushRemote(cfg, merged, shas.backup);
      // refresh the human-readable log when sessions changed (or README missing)
      const sessionsChanged =
        !remoteNorm || !same(merged.sessions, remoteNorm.sessions);
      if (sessionsChanged || !shas.readme) {
        await pushReadme(cfg, merged.sessions, (await remoteShas(cfg)).readme);
      }
    }
    return { status: 'ok', changedLocal, sessions: merged.sessions.length };
  };

  let result;
  try {
    result = await doPass();
  } catch (e) {
    if (!e.conflict) {
      setLastSync({ status: 'error', message: e.message });
      throw e;
    }
    // Someone else pushed between our fetch and put — brief pause, once more
    await new Promise((r) => setTimeout(r, 800));
    try {
      result = await doPass();
    } catch (e2) {
      const msg = e2.conflict
        ? 'Sync conflict — another device is syncing right now. It will resolve on the next sync.'
        : e2.message;
      setLastSync({ status: 'error', message: msg });
      throw e2.conflict ? new Error(msg) : e2;
    }
  }
  setLastSync({ status: 'ok', sessions: result.sessions });
  return result;
}
