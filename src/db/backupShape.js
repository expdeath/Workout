// ── Backup shape: normalize + merge (pure, no I/O) ───────────────
// The canonical JSON shape of one account's data — what coach-backup.json
// in the GitHub repo holds, what Export/Import use, and what the
// Firestore codec (firestoreCodec.js) converts to and from documents.

const sessionId = (s) => s.id || s.date;

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

  // deletion log: union, newest timestamp per id (deletion always wins
  // over a live copy still sitting on another device)
  const delById = new Map();
  for (const d of [...(local.deletedIds || []), ...(remote.deletedIds || [])]) {
    if (d?.id && (d.at || 0) > (delById.get(d.id) || 0)) delById.set(d.id, d.at || 0);
  }
  const deletedIds = [...delById].map(([id, at]) => ({ id, at }));
  const seen = new Set();
  const events = [];
  for (const e of [...(local.events || []), ...(remote.events || [])]) {
    if (!e?.type || seen.has(eventKey(e))) continue;
    seen.add(eventKey(e));
    events.push(e);
  }
  // AI settings (profile/routine): newest edit wins
  const lc = local.aiSettings || {};
  const rc = remote.aiSettings || {};
  const aiSettings = (rc.updatedAt || 0) > (lc.updatedAt || 0) ? rc : lc;

  // health rows: union by date, freshest reading wins
  const byDate = new Map();
  for (const h of remote.health || []) if (h?.date) byDate.set(h.date, h);
  for (const h of local.health || []) {
    if (!h?.date) continue;
    const r = byDate.get(h.date);
    byDate.set(h.date, !r || (h.receivedAt || 0) >= (r.receivedAt || 0) ? h : r);
  }

  return normalizeBackup({
    ...local,
    sessions: [...byId.values()],
    events,
    health: [...byDate.values()],
    aiSettings,
    deletedIds,
  });
}

/** Deterministic shape so backups can be compared as JSON strings. */
export function normalizeBackup(b) {
  // deletion log: legacy in-place tombstones (deleted:true rows) fold
  // into it, sessions carry only real workouts. Markers are kept
  // permanently — a few bytes each, and no device can ever resurrect
  // a deleted workout, however long it was offline.
  const dels = new Map((b.deletedIds || []).map((d) => [d.id, d.at || 0]));
  const sessions = [];
  for (const s of b.sessions || []) {
    if (!s?.date) continue;
    const id = sessionId(s);
    if (s.deleted) {
      if (!dels.has(id)) dels.set(id, s.updatedAt || Date.now());
      continue;
    }
    if (!dels.has(id)) sessions.push({ ...s, id });
  }
  return {
    app: 'coach',
    version: b.version || 1,
    aiSettings: b.aiSettings || {},
    deletedIds: [...dels]
      .map(([id, at]) => ({ id, at }))
      .sort((a, x) => a.id.localeCompare(x.id)),
    health: [...(b.health || [])].sort((a, x) => (a.date < x.date ? -1 : 1)),
    sessions: sessions.sort((a, x) => (a.date + a.id).localeCompare(x.date + x.id)),
    events: (b.events || [])
      .map(({ id, ...e }) => e)
      .sort((a, x) => (eventKey(a) < eventKey(x) ? -1 : 1)),
    // saved workouts + Settings switches (state workout-<id> / prefs);
    // only present when there are any — the iOS Backup model matches
    ...(b.workouts?.length ? { workouts: [...b.workouts].sort((a, x) => String(a.id).localeCompare(String(x.id))) } : {}),
    ...(b.prefs ? { prefs: b.prefs } : {}),
  };
}

