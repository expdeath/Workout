# Cloud Firestore — schema, rules, migration

COACH's live database moves from one `coach-backup.json` per GitHub
repo to Cloud Firestore, shared by the web app and the iOS app. The
GitHub data repos stay as a backup that clients keep writing.

Decisions behind this (made 2026-10-07): Google sign-in now (Apple
later, once enrolled in the Apple Developer Program); an owner-managed
email allowlist instead of invite codes; one shared Gemini key in
`config/shared`; exercise photos/clips stay on the device; Watch data
moves to native HealthKit in the iOS app (the Shortcut → GitHub
`health-inbox/` pipeline keeps working until then).

## Schema

```
allowlist/{email}                  { accountId, name, admin }      owner-managed only
config/shared                      { geminiKey }                   read: any allow-listed user
accounts/{accountId}               { name, backupMeta{app,version}, github{repo,token},
                                     migratedFrom{repo,at,inboxFiles}, createdAt }
accounts/{a}/sessions/{id}          one workout — same object as before
accounts/{a}/health/{date}          one day of Watch data
accounts/{a}/deletedIds/{id}        { id, at } — permanent deletion marker
accounts/{a}/events/{iso|type}      one event-log entry (id = the merge dedupe key)
accounts/{a}/state/aiSettings       profile / routine / goals / equipment / cueNotes / barKg / plates
accounts/{a}/state/{key}            today · weeklyReview · monthlyReport · chat-YYYY-MM-DD ·
                                     healthText-YYYY-MM-DD   (formerly browser-only)
accounts/{a}/feedback/{auto}        { text, name, at }
```

Account ids: `abhi` (owner/admin), `karan`. Keshav and Jake never used the
app; they were not migrated and their data repos are being deleted. Data is keyed by
account, not by Firebase user id, so one person can sign in with more
than one identity (e.g. Google now, Apple later) by adding a second
allowlist entry pointing at the same account.

### Encoding (`src/db/firestoreCodec.js`, iOS port to follow)

Firestore can't store an array directly inside an array, and every
session's `log` is `[[set, …], …]`. Values pass through
`encodeValue`/`decodeValue`: an inner array becomes `{ "__a": [...] }`,
and an object with a key Firestore can't hold (`""`, `__…`) becomes
`{ "__m": [{k, v}, …] }`. Lossless for any JSON value. Document ids
escape `/` and `%`; the real key is always also inside the document.

## Rules (`firestore.rules`)

- Signed in + verified email + on the allowlist, or nothing.
- Users read/write only their own account; the owner (`admin: true`)
  can read every account (as they could read every data repo).
- **Deletion wins**: a session can't be written while a `deletedIds`
  marker exists for it.
- **Newer wins**: a session or `aiSettings` write with an older
  `updatedAt` than the stored copy is rejected (the old merge's
  `pickSession` / newest-settings rule).
- Clients can't edit the allowlist or an account's name/metadata.

## Migration (`scripts/migrate-to-firestore.js`)

Reads each account's `coach-backup.json` **and any undrained
`health-inbox/` files** from GitHub (read-only), normalizes them with
the apps' own `normalizeBackup`, converts to documents, checks every
document against Firestore's limits, and verifies the conversion round
trip. In live mode it writes, reads everything back from Firestore and
deep-compares again; any difference fails the run.

```sh
cp scripts/firestore-accounts.example.json scripts/firestore-accounts.json   # gitignored
# fill in projectId, emails, geminiKey
node scripts/migrate-to-firestore.js --dry-run
npm i --no-save firebase-admin
node scripts/migrate-to-firestore.js --key ~/coach-firebase.service-account.json
```

Migrated 2026-10-07 into project `heath-9a322`: 2,307 documents, read back
from Firestore and identical to the source:

| Account | Sessions | Events | Health days | Deletion markers |
|---|---|---|---|---|
| abhi | 39 | 1,594 | 166 (163 + 3 undrained inbox files) | 6 |
| karan | 31 | 469 | 0 | 0 |

Not migrated, by decision: data that only ever lived in one browser
(reports, chat, in-progress workout, media). The GitHub repos keep
their full git history, so the pre-migration state stays recoverable.

## Known data quirk (not fixed)

When the Watch sends `ExerciseMin:` with no value, `parseHealthNumbers`
reads the next metric's number (e.g. 2026-09-16 stored
`exerciseMin: 1.54`, which is actually `distKm`). Migrated as-is.
