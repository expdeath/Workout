#!/usr/bin/env node
// ── Invite code generator (owner-only, runs locally) ─────────────
// An account = a private data repo + a fine-grained PAT scoped to it
// (+ optionally a Gemini key). This packs those into the base64url
// code that the app's login screen redeems.
//
//   node scripts/make-invite.js --name Karan \
//     --repo expdeath/coach-data-karan \
//     --token github_pat_xxx \
//     [--gemini AIzaSy_xxx]
//
// With a token present it verifies repo access before printing.

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
}

const { name, repo, token, gemini } = args;
if (!name || !repo || !token) {
  console.error('Usage: node scripts/make-invite.js --name <Name> --repo <owner/repo> --token <PAT> [--gemini <key>]');
  process.exit(1);
}

async function verify() {
  const res = await fetch(`https://api.github.com/repos/${repo}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!res.ok) {
    console.error(`✗ Token can't see ${repo} (GitHub ${res.status}).`);
    console.error('  Check: fine-grained PAT, Repository access = only this repo, Contents = Read and write.');
    process.exit(1);
  }
  const info = await res.json();
  if (!info.private) {
    console.error(`✗ ${repo} is PUBLIC — training data would be world-readable. Make it private first.`);
    process.exit(1);
  }
  if (!info.permissions?.push) {
    console.error('✗ Token has no write access — sync would fail. Grant Contents: Read and write.');
    process.exit(1);
  }
  console.error(`✓ ${repo} — private, token has write access.`);
}

await verify();

const code = Buffer.from(
  JSON.stringify({ v: 1, name, repo, ghToken: token, ...(gemini ? { geminiKey: gemini } : {}) })
).toString('base64url');

console.error(`\nMagic link for ${name}${gemini ? ' (Gemini key included)' : ' (no Gemini key — they add their own in Settings)'} — they tap it and they're in:\n`);
console.log(`https://expdeath.github.io/Workout/#invite=${code}`);
console.error('\nOr the bare code (pasted into the app\'s login box):\n');
console.log(code);
console.error('\nSend either privately (WhatsApp/Signal) — the link IS the credential.');
