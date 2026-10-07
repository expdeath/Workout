# Accounts (invite-only, Google sign-in)

There is no signup. People sign in with Google, and only emails on the
Firestore **allowlist** get in. Each allowlist entry points at one
**account**, which holds that person's data (schema: `firestore.md`).
The same sign-in works in the web app and the iOS app.

Current accounts (2026-10-07): `abhi` (owner, `admin: true`) and
`karan`.

## Add a person (~3 minutes, Firebase console)

Firebase console → project **heath** → Firestore Database → Data:

1. **Create their account**: collection `accounts` → Add document →
   Document ID e.g. `jane` (lowercase, no spaces). Fields:
   - `name` (string): `Jane`
   - `github` (map): `repo` (string): `expdeath/coach-data-jane` — only
     if they get a GitHub backup repo; see below. Otherwise leave
     `github` as an empty map.
2. **Let their Google email in**: collection `allowlist` → Add
   document → Document ID = their Google email, **all lowercase**.
   Fields: `accountId` (string): `jane`, `name` (string): `Jane`,
   `admin` (boolean): `false`.
3. Send them the link: https://expdeath.github.io/Workout/ — they tap
   **Sign in with Google** with that email.

A second sign-in identity for the same person (e.g. Sign in with Apple
later) = one more allowlist entry with the same `accountId`.

### Optional: GitHub backup for them
Create a private repo (`expdeath/coach-data-jane`), a fine-grained token
(Contents read/write, that repo only), set the repo in step 1, and paste
the token into **Settings → Sync & Backup** while signed in as them —
or add `token` to their account's `github` map in the console.

## Day-to-day

- **Feedback**: Settings → Send feedback writes to
  `accounts/<id>/feedback` — read it in the console.
- **Revoking someone**: delete their `allowlist` document. Their data
  stays in `accounts/<id>`.
- **The Gemini key** is one shared key in `config/shared` (`geminiKey`),
  readable by every allow-listed user. Change it in the web app's
  Settings → AI Coach while signed in as the owner.
