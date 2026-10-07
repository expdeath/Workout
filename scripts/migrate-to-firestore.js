#!/usr/bin/env node
// ── GitHub data repos → Cloud Firestore ──────────────────────────
// Copies every account's coach-backup.json (plus any undrained
// health-inbox/ files) into Firestore, then reads it all back and
// proves the round trip is lossless. GitHub is only ever READ — the
// repos keep their data, and stay the backup target afterwards.
//
//   node scripts/migrate-to-firestore.js --config scripts/firestore-accounts.json --dry-run
//   node scripts/migrate-to-firestore.js --config scripts/firestore-accounts.json \
//        --key path/to/service-account.json [--only karan]
//
// --dry-run needs no Firebase at all: it fetches, converts, checks
// every document against Firestore's limits and verifies the
// conversion round trip in memory.
//
// GitHub auth: $GITHUB_TOKEN, else the token macOS keychain holds
// for github.com (`git credential fill`). Config format: see
// scripts/firestore-accounts.example.json (the real file holds
// people's emails, so it is gitignored).

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { normalizeBackup } from '../src/db/backupShape.js';
import { parseHealthNumbers } from '../src/utils/stats.js';
import { backupToDocs, docsToBackup } from '../src/db/firestoreCodec.js';

const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
const opt = (n) => {
  const i = args.indexOf(`--${n}`);
  return i >= 0 ? args[i + 1] : undefined;
};

const DRY = flag('dry-run');
const config = JSON.parse(readFileSync(opt('config') || 'scripts/firestore-accounts.json', 'utf8'));
const only = opt('only');

// ── GitHub (read-only) ───────────────────────────────────────────

function githubToken() {
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN;
  const out = execFileSync('git', ['credential', 'fill'], {
    input: 'protocol=https\nhost=github.com\n\n',
    encoding: 'utf8',
  });
  const t = /^password=(.*)$/m.exec(out)?.[1];
  if (!t) throw new Error('No GitHub token: set GITHUB_TOKEN.');
  return t;
}
const GH = githubToken();

async function gh(path, raw = false) {
  const res = await fetch(`https://api.github.com${path}`, {
    headers: {
      Authorization: `Bearer ${GH}`,
      Accept: raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`GitHub ${res.status} for ${path}`);
  return raw ? res.text() : res.json();
}

/** The repo's backup + its undrained Watch inbox files. */
async function readRepo(repo) {
  const text = await gh(`/repos/${repo}/contents/coach-backup.json?ref=main`, true);
  const backup = text ? JSON.parse(text) : { sessions: [] };
  const listing = (await gh(`/repos/${repo}/contents/health-inbox?ref=main`)) || [];
  const inbox = [];
  for (const f of listing.filter((x) => x?.type === 'file')) {
    inbox.push({ name: f.name, body: await gh(`/repos/${repo}/contents/health-inbox/${encodeURIComponent(f.name)}?ref=main`, true) });
  }
  return { backup, inbox, bytes: text?.length || 0 };
}

// ── Health inbox → health rows ───────────────────────────────────
// Exactly what the app does when it drains a file: consumeHealthInbox
// (src/db/sync.js) mergeHealth()s the core four fields + raw, then the
// boot-time reparseHealthRows (src/utils/healthIngest.js) fills every
// other field the parser finds that the row is missing.

function parseInboxBody(body) {
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
    } catch { /* plain text */ }
  }
  return { text: t };
}

function applyInbox(backup, inbox, now) {
  const health = new Map((backup.health || []).map((h) => [h.date, h]));
  const applied = [];
  for (const f of inbox) {
    const date = /(\d{4}-\d{2}-\d{2})/.exec(f.name)?.[1];
    if (!date) {
      applied.push({ file: f.name, skipped: 'no date in filename' });
      continue;
    }
    const { text, nums } = parseInboxBody(f.body);
    const asText = nums
      ? [
          nums.hrv && `HRV ${nums.hrv} ms`,
          nums.rhr && `RHR ${nums.rhr}`,
          nums.sleepH && `Sleep ${nums.sleepH}h`,
          nums.weightKg && `Weight ${nums.weightKg}kg`,
          nums.steps && `Steps ${nums.steps}`,
        ].filter(Boolean).join(' · ')
      : text;
    if (!asText) {
      applied.push({ file: f.name, skipped: 'empty' });
      continue;
    }
    const n = parseHealthNumbers(asText);
    let row = {
      ...(health.get(date) || {}),
      date,
      hrv: n.hrv || null,
      rhr: n.rhr || null,
      steps: n.steps || null,
      sleepH: n.sleepH || null,
      raw: asText.slice(0, 300),
      receivedAt: now,
    };
    if (nums) row = { ...row, ...nums, receivedAt: now };
    for (const [k, v] of Object.entries(parseHealthNumbers(row.raw))) {
      if (v && (row[k] == null || (k === 'sleepH' && row[k] > 11))) row[k] = v;
    }
    health.set(date, row);
    applied.push({ file: f.name, date });
  }
  return { backup: { ...backup, health: [...health.values()] }, applied };
}

// ── Firestore's limits, checked before anything is written ───────

const MAX_DOC_BYTES = 1_048_576 - 1_500; // 1 MiB minus room for the name

function checkDoc(path, data) {
  const problems = [];
  const walk = (v, where, inArray) => {
    if (v === undefined) problems.push(`${where}: undefined`);
    else if (typeof v === 'number' && !Number.isFinite(v)) problems.push(`${where}: ${v}`);
    else if (Array.isArray(v)) {
      if (inArray) problems.push(`${where}: array inside array`);
      v.forEach((x, i) => walk(x, `${where}[${i}]`, true));
    } else if (v && typeof v === 'object') {
      for (const [k, x] of Object.entries(v)) {
        if (k === '' || /^__.*__$/.test(k)) problems.push(`${where}: bad field name "${k}"`);
        walk(x, `${where}.${k}`, false);
      }
    }
  };
  walk(data, path, false);
  const size = Buffer.byteLength(JSON.stringify(data));
  if (size > MAX_DOC_BYTES) problems.push(`${path}: ${size} bytes > 1 MiB`);
  return problems;
}

// order-independent deep compare (Firestore hands maps back key-sorted)
function canon(v) {
  if (Array.isArray(v)) return v.map(canon);
  if (v && typeof v === 'object') {
    return Object.fromEntries(Object.keys(v).sort().map((k) => [k, canon(v[k])]));
  }
  return v;
}
const sameData = (a, b) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));

function firstDiff(a, b, path = '') {
  if (sameData(a, b)) return null;
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = firstDiff(a[k], b[k], `${path}.${k}`);
      if (d) return d;
    }
  }
  return `${path || '(root)'}: ${JSON.stringify(a)?.slice(0, 120)} ≠ ${JSON.stringify(b)?.slice(0, 120)}`;
}

// ── Firestore (live mode only) ───────────────────────────────────

async function openFirestore() {
  const { initializeApp, cert } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  const keyPath = opt('key') || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!keyPath) throw new Error('Live mode needs --key <service-account.json>.');
  const key = JSON.parse(readFileSync(keyPath, 'utf8'));
  if (config.projectId && key.project_id !== config.projectId) {
    throw new Error(`Key is for ${key.project_id}, config says ${config.projectId}.`);
  }
  initializeApp({ credential: cert(key) });
  return getFirestore();
}

const SUBCOLS = ['sessions', 'health', 'deletedIds', 'events', 'state'];

async function writeAccount(db, acct, meta, docs, sourceInfo) {
  const root = db.collection('accounts').doc(acct.id);
  const existing = await root.get();
  if (existing.exists && !flag('overwrite')) {
    throw new Error(`accounts/${acct.id} already exists — rerun with --overwrite to replace it.`);
  }
  // --overwrite: clear what's there so the result equals the source exactly
  if (existing.exists) {
    for (const col of SUBCOLS) await db.recursiveDelete(root.collection(col));
  }
  const writer = db.bulkWriter();
  writer.set(root, {
    name: acct.name,
    backupMeta: meta,
    github: { repo: acct.repo, ...(existing.data()?.github?.token ? { token: existing.data().github.token } : {}) },
    migratedFrom: sourceInfo,
    createdAt: existing.data()?.createdAt ?? Date.now(),
  });
  for (const d of docs) writer.set(root.collection(d.col).doc(d.id), d.data);
  await writer.close();
}

async function readAccount(db, accountId) {
  const root = db.collection('accounts').doc(accountId);
  const snap = await root.get();
  const docs = [];
  for (const col of SUBCOLS) {
    const qs = await root.collection(col).get();
    qs.forEach((d) => docs.push({ col, id: d.id, data: d.data() }));
  }
  return { meta: snap.data()?.backupMeta || {}, docs };
}

async function writeAllowlist(db) {
  const writer = db.bulkWriter();
  for (const a of config.accounts) {
    for (const email of a.emails || []) {
      writer.set(db.collection('allowlist').doc(email.trim().toLowerCase()), {
        accountId: a.id,
        name: a.name,
        admin: !!a.admin,
      });
    }
  }
  await writer.close();
}

// ── Main ─────────────────────────────────────────────────────────

const counts = (b) =>
  `${b.sessions.length} sessions · ${b.events.length} events · ${b.health.length} health days · ${b.deletedIds.length} deletions · aiSettings ${Object.keys(b.aiSettings).length} keys`;

const db = DRY ? null : await openFirestore();
const now = Date.now();
let failed = false;

for (const acct of config.accounts) {
  if (only && acct.id !== only) continue;
  console.log(`\n── ${acct.id} (${acct.repo})`);
  const { backup: raw, inbox, bytes } = await readRepo(acct.repo);
  console.log(`  GitHub: ${bytes.toLocaleString()} bytes · ${inbox.length} health-inbox file(s)`);

  // what normalizing alone changes (legacy deleted:true rows → deletion markers)
  const legacyDeleted = (raw.sessions || []).filter((s) => s?.deleted).map((s) => s.id || s.date);
  if (legacyDeleted.length) {
    console.log(`  note: ${legacyDeleted.length} legacy deleted session(s) become deletion markers, as the apps already treat them: ${legacyDeleted.join(', ')}`);
  }

  const { backup: withInbox, applied } = applyInbox(raw, inbox, now);
  for (const a of applied) console.log(`  inbox ${a.file} → ${a.date ? `health ${a.date}` : `SKIPPED (${a.skipped})`}`);

  const expected = normalizeBackup(withInbox);
  const { meta, docs } = backupToDocs(withInbox);
  console.log(`  source: ${counts(expected)}`);
  console.log(`  → ${docs.length} Firestore documents`);

  const problems = docs.flatMap((d) => checkDoc(`${d.col}/${d.id}`, d.data));
  const ids = new Set();
  for (const d of docs) {
    const p = `${d.col}/${d.id}`;
    if (ids.has(p)) problems.push(`${p}: duplicate document id`);
    ids.add(p);
  }
  if (problems.length) {
    failed = true;
    console.log(`  ✗ ${problems.length} Firestore limit problem(s):\n    ${problems.slice(0, 20).join('\n    ')}`);
    continue;
  }

  // in-memory round trip (JSON is what Firestore can represent)
  const memBack = docsToBackup({ meta, docs: JSON.parse(JSON.stringify(docs)) });
  const memDiff = firstDiff(expected, memBack);
  if (memDiff) {
    failed = true;
    console.log(`  ✗ conversion round trip differs: ${memDiff}`);
    continue;
  }
  console.log('  ✓ conversion round trip identical');

  if (DRY) continue;

  await writeAccount(db, acct, meta, docs, {
    repo: acct.repo,
    at: new Date(now).toISOString(),
    inboxFiles: applied.filter((a) => a.date).map((a) => a.file),
  });
  const back = docsToBackup(await readAccount(db, acct.id));
  const diff = firstDiff(expected, back);
  if (diff) {
    failed = true;
    console.log(`  ✗ Firestore read-back differs: ${diff}`);
  } else {
    console.log(`  ✓ Firestore read-back identical: ${counts(back)}`);
  }
}

if (!DRY && !only) {
  await writeAllowlist(db);
  console.log('\nallowlist written');
  if (config.geminiKey) {
    await db.collection('config').doc('shared').set({ geminiKey: config.geminiKey }, { merge: true });
    console.log('shared config (Gemini key) written');
  } else {
    console.log('no geminiKey in config — config/shared not written');
  }
}

console.log(failed ? '\n✗ FAILED — see above' : `\n✓ ${DRY ? 'dry run' : 'migration'} OK`);
process.exit(failed ? 1 : 0);

