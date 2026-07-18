---
name: shortcut
description: Decompile, modify, re-sign, install, and verify the Gym Check-in Apple Shortcut that uploads Watch health data to the GitHub health inbox.
---

# Building / modifying the Gym Check-in shortcut

The shortcut reads Health data (HRV, resting HR, steps) on the iPhone and
PUTs it as one file into `health-inbox/` of the user's private data repo
(`expdeath/workout-data`). The app drains that folder on every sync
(`consumeHealthInbox` in [sync.js](../../../src/db/sync.js)) — parses the
payload, merges it into the health store, pre-fills today's check-in, and
deletes the file. The current public build lives at
`public/gym-checkin-v10.shortcut`; the user's installed copy is
"Gym Check-in v12" (v10 + credentials baked in).

## Decompile a signed .shortcut

Signed shortcuts are AEA containers wrapping an Apple Archive wrapping the
real payload, `Shortcut.wflow` (a binary plist). The signer's public key is
embedded in the AEA auth-data header — extract it, then unwrap:

```bash
python3 - <<'EOF'
import struct, plistlib
data = open('gym-checkin-v10.shortcut','rb').read()
authlen = struct.unpack('<I', data[8:12])[0]          # AEA1 magic, LE len at 8
auth = plistlib.loads(data[12:12+authlen])
open('leaf.der','wb').write(auth['SigningCertificateChain'][0])
EOF
openssl x509 -inform der -in leaf.der -pubkey -noout > leaf.pem
aea decrypt -i gym-checkin-v10.shortcut -o payload.aar -sign-pub leaf.pem
aa extract -i payload.aar -d out          # → out/Shortcut.wflow
plutil -convert xml1 out/Shortcut.wflow -o wf.xml   # human-readable
```

## Anatomy of the workflow (24 actions)

- **0–14**: triplets of `gettext` (label) → `filter.health.quantity` →
  `statistics` → `appendvariable` into the `CoachData` variable, one per
  metric (HRV, RHR, steps). Copy this pattern to add a metric (e.g. sleep).
- **15** `text.combine` — joins CoachData with a space → "Combined Text".
- **16** `setclipboard` — legacy fallback so a paste into the app works.
- **17, 18** `gettext` — the repo (`user/repo`) and GitHub token. These are
  what the two `WFWorkflowImportQuestions` target (by `ActionIndex`).
- **19, 20** date actions — vestigial; the filename no longer uses them
  (see gotchas).
- **21** `base64encode` — MUST have `WFBase64LineBreakMode: 'None'`.
- **22** `downloadurl` — `PUT
  https://api.github.com/repos/{17}/contents/health-inbox/{date}.json`,
  headers `Authorization: Bearer {18}` + `Accept:
  application/vnd.github+json`, JSON body `{message, content: {21},
  branch: "main"}`.
- **23** `showresult` — displays "GitHub said: {response}" so failures are
  visible. Never remove this; Shortcuts ignores HTTP errors otherwise.

Text tokens embed variables as `￼` placeholder chars with an
`attachmentsByRange` dict keyed `"{charIndex, 1}"` — indexes count the
placeholder itself, and every attachment is exactly 1 char.

## Health sample types — naming and category traps

The filter's Type enumeration must use the SHORTCUTS PICKER's names,
which follow the Health app's display names — not HealthKit developer
names. Verified working: `Heart Rate Variability`, `Resting Heart Rate`,
`Steps`, `Sleep` (NOT "Sleep Analysis" — that string is silently treated
as an unknown/quantity type: phantom Unit row, zero results), `Cardio
Fitness` (NOT "VO2 Max"), `Active Energy`, `Exercise Minutes`,
`Walking + Running Distance`, `Respiratory Rate`, `Wrist Temperature`.
When unsure, have the user re-pick the type in the Shortcuts editor —
the picker writes ground truth — and read what it chose.

Sleep is a category type: samples coerce to stage-name TEXT, so
Statistics errors with "couldn't convert from Text to Number". Sum the
samples' `Duration` property instead — put an aggrandizement on the
statistics input token:
`'Aggrandizements': [{'Type':'WFPropertyVariableAggrandizement','PropertyName':'Duration'}]`
The duration sum arrives in SECONDS. Also add a `Value is Asleep`
filter, otherwise In Bed segments double the total. Never set
`WFHKSampleFilteringUnit` on a category type — it breaks the query.

A Find action with zero results shows a blocking "No Samples Found"
alert that ABORTS the whole run (no upload). Health read permissions:
Health app → profile → Privacy → Apps → Shortcuts. Health actions
error on macOS, so full runs are iPhone-only.

## Gotchas that cost real debugging time

- **Base64 line breaks**: Shortcuts wraps base64 at 76 chars by default;
  GitHub strict-decodes and 422s ("content is not valid Base64"). Short
  test payloads (<76 chars) pass, real ones fail — always test with a
  long payload. Fix: `WFBase64LineBreakMode: 'None'` on action 21.
- **Date/Format Date outputs resolve empty on iOS** (filename became
  `.json`, so a second same-day run 422s on the existing path). Use an
  inline Current Date token in the URL instead:
  ```python
  url['attachmentsByRange']['{53, 1}'] = {
    'Type': 'CurrentDate',
    'Aggrandizements': [{'Type': 'WFDateFormatVariableAggrandizement',
                         'WFDateFormatStyle': 'Custom',
                         'WFDateFormat': 'yyyy-MM-dd-HHmmss'}]}
  ```
- **Shortcuts never surfaces HTTP errors** — a 401/404/422 run looks
  "perfect" to the user. Keep the Show Result action.
- **Import questions get skipped by iOS sometimes**; the personal-build
  path below avoids them entirely.
- Health actions (`filter.health.quantity`) error on macOS ("not supported
  on Mac") — a full run only works on iPhone. Test the PUT itself with
  curl (same URL/headers/body shape) from the Mac.

## Rebuild, sign, ship

```bash
# edit the plist with python plistlib, then:
plutil -convert binary1 wf.xml -o unsigned.shortcut   # or plistlib FMT_BINARY
shortcuts sign --mode anyone --input unsigned.shortcut --output signed.shortcut
```

Two variants:

- **Public** (import questions intact) → `public/gym-checkin-vN.shortcut`,
  update the link + version text in Settings.jsx (Apple Watch card),
  commit, push (auto-deploys).
- **Personal** (zero-friction): set actions 17/18's `WFTextActionText` to
  the real repo and token (token via `git credential fill`, see memory),
  delete `WFWorkflowImportQuestions`, name it "Gym Check-in vN.shortcut",
  sign, then `open` it — the Mac Shortcuts app shows an Add dialog the
  user must click, and iCloud syncs it to the iPhone (~1 min). Poll
  `shortcuts list | grep "vN"` to detect the click. NEVER commit a
  file containing the token; build it in the scratchpad.

Bump the version in the shortcut's display name every time — the user
must be able to tell copies apart to delete stale ones.

## Verify a delivery

```bash
TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill | grep password | cut -d= -f2)
# file arrives: GET /repos/expdeath/workout-data/contents/health-inbox
# after the user opens the app: folder empty + today's row in coach-backup.json .health[]
```

A test PUT with payload `{"health":""}` is safe — the drain treats it as
empty and just deletes it.
