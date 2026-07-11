import 'fake-indexeddb/auto';
const ls = new Map();
globalThis.localStorage = { getItem: k => ls.get(k) ?? null, setItem: (k,v) => ls.set(k,String(v)), removeItem: k => ls.delete(k) };
const db = await import('./src/db/db.js');
const sync = await import('./src/db/sync.js');
const assert = (c, m) => { if (!c) { console.error('FAIL:', m); process.exit(1); } console.log('ok:', m); };

sync.setSyncConfig({ token: process.env.GH_TOKEN, repo: 'expdeath/workout-data-test' });
await db.putSession({ id: '2026-07-11#1', date: '2026-07-11', finished: true, fin: { rpe: 7 },
  plan: { sessionType: 'Pull', exercises: [{ name: 'Lat Pulldown' }] },
  log: [[{ weight: '55', reps: '8', done: true }, { weight: '57', reps: '6', done: true }]] });
const r = await sync.syncNow();
assert(r.status === 'ok', 'sync ran');

const hdr = { Authorization: `Bearer ${process.env.GH_TOKEN}`, Accept: 'application/vnd.github.raw+json' };
const backup = await (await fetch('https://api.github.com/repos/expdeath/workout-data-test/contents/coach-backup.json?ref=main', { headers: hdr })).text();
assert(backup.includes('\n  '), 'backup is pretty-printed');
const readme = await (await fetch('https://api.github.com/repos/expdeath/workout-data-test/contents/README.md?ref=main', { headers: hdr })).text();
assert(readme.includes('| Fri 11 Jul | Pull | 7 |'), 'README table has the session row');
assert(readme.includes('Lat Pulldown 57×6'), 'README shows top set');
console.log('--- README preview ---'); console.log(readme.split('\n').slice(0, 14).join('\n'));
console.log('ALL PASSED');
