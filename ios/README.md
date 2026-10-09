# COACH — native iOS app

A native SwiftUI rewrite of the COACH web app (`../src`), living in
`ios/CoachApp/`. Same data (Cloud Firestore, shared live with the web
app), same Google sign-in, same Gemini AI coach — a from-scratch port, not a wrapper around the website. This
file tracks what's actually done, what's left, and exactly what to do
next.

## Status at a glance

| Area | Status |
|---|---|
| Data models (Session/Plan/Backup/etc.) | ✅ Done, tested |
| Cloud Firestore (live data, shared with the web app) | ✅ Done — codec tested; byte-identical documents to the web app on all real data |
| GitHub backup + Watch inbox drain | ✅ Done, tested |
| Training stats / progression math | ✅ Done, tested |
| Gemini AI client | ✅ Done, tested |
| Google sign-in + allowlist | ✅ Built — needs a simulator/device run (see "Immediate next step") |
| Visual theme (colors/fonts matching the website) | ✅ Done (Login, Home) |
| Login screen | ✅ Done |
| Home screen | ✅ Done (quick cardio can be backdated, like the web) |
| CheckIn screen | ✅ Done |
| Generating screen | ✅ Done |
| Past workout screen (`src/screens/AddPast.jsx`) | ✅ Done, UI-tested |
| Workout screen (rest timer, set logging) | ✅ Done — UI-tested (set → rest timer → plates → effort → finish) |
| Finish screen | ✅ Done (PR banner + confetti) |
| History / HistoryDetail screens | ✅ Done, UI-tested (edit, delete, scoped chat) |
| Records screen | ✅ Done |
| Progress screen (charts) | ✅ Done (Swift Charts) |
| Settings screen | ✅ Done (export/import/CSV, backup, sign out, Apple Health) |
| Coach chat sheet | ✅ Done (shared chat-<date> with the web) |
| My workouts (own + trainer's, schedule, add-ons, build with coach from text/photo) | ✅ Done, unit-tested (shared `workout-<id>` state with the web) |
| Search · Records share/export · Alerts & reports switches | ✅ Done (shared `prefs` state with the web) |
| HealthKit | ✅ Built + unit-tested; needs a run on the real iPhone (Settings → Connect Apple Health) |
| App Store / TestFlight distribution | Deliberately deferred — see "Distribution" below |

81 unit tests (`CoachAppTests/`) and 5 UI tests (`CoachAppUITests/`), all
passing on the iPhone 17 simulator (2026-10-09). `COACH_DEBUG_WORKOUTS=1`
with the debug seed adds saved workouts; `COACH_DEBUG_SCREEN=workouts`
opens My workouts.
The unit tests pass (run on macOS on 2026-10-07 — see "Dev workflow"
for why). The UI tests and the Firestore/Google sign-in flow haven't
run since the move to Firestore: the simulator was unavailable (Xcode 27
was missing its CoreSimulator update).

## How this app relates to the website

Same backend, two frontends. Both sign in with Google against the same
Firestore allowlist, read and write the same Firestore documents
(schema, rules and decisions: `../docs/firestore.md`), and call Gemini
directly with the same prompts and the same shared key. A workout
logged in one app shows up in the other within seconds. Both apps
encode documents identically (`Sync/FirestoreCodec.swift` is a port of
`src/db/firestoreCodec.js`, verified against all real data). When in
doubt about "what should this do," the answer is "whatever the
matching JS file in `../src` does" — that's the actual spec.

## Architecture

```
ios/CoachApp/
  project.yml                XcodeGen spec — the source of truth for
                              the Xcode project. Edit this, not the
                              .xcodeproj, then run `xcodegen generate`.
  CoachApp/
    App/
      CoachApp.swift          @main entry point
      AppState.swift          root observable state machine — ports
                               src/App.jsx (screen state, boot, sync
                               orchestration, check-in→plan→workout→
                               finish flow, weekly/monthly reports)
      RootView.swift          switches on AppState.screen
      Theme.swift              colors/fonts ported from src/index.css
      DebugSeed.swift          #if DEBUG-only: COACH_DEBUG_SEED=1 runs the
                               app fully offline (Cloud.offline) with a
                               fake account + seeded session, for UI
                               tests/screenshots without a Google sign-in
    Models/                   Codable structs mirroring the exact JSON
                               shapes the web app writes. Lenient and
                               lossless — see "Gotcha: lenient decoding".
                               RawPreserving.swift: documents keep the
                               JSON they came from and write back only
                               changed fields.
    Persistence/
      LocalStore.swift        the signed-in account's data in memory
                               (the `Backup` shape screens read), kept
                               live by Cloud's listeners; mutations
                               write through to Firestore
      Keychain.swift           only to carry invite-era secrets over once
      Defaults.swift            small per-device settings (UserDefaults)
    Sync/
      Cloud.swift              Firestore + Google sign-in — port of
                               src/db/cloud.js: allowlist → account,
                               snapshot listeners, background writes,
                               shared state (today, reports, chat)
      FirestoreCodec.swift     port of src/db/firestoreCodec.js
      GitHubSync.swift        port of src/db/sync.js: GitHub backup
                               (coach-backup.json + README) + Watch
                               health-inbox drain
    Stats/
      Stats.swift              full port of src/utils/stats.js
      Helpers.swift            date formatting + set-input clamping,
                               ports src/utils/helpers.js
    AI/
      GeminiClient.swift       full port of src/api/gemini.js
      AIContext.swift          ports src/utils/aiContext.js
    Account/
      Account.swift            Google sign-in / sign-out, ports
                               src/utils/account.js
    Screens/                  one SwiftUI view per src/screens/*.jsx
    Components/                one SwiftUI view per src/components/*.jsx
    Resources/Fonts/           bundled Barlow Condensed + Space Grotesk
                               .ttf files (see "Gotcha: fonts" below)
  CoachAppTests/               XCTest target, 64 tests
```

**Design principle**: port the existing JS logic faithfully rather than
redesign it. `stats.js`, `sync.js`, `gemini.js`, `account.js` are plain
functions with no DOM/React coupling — they translate close to 1:1.
When adding a new screen, open the matching `src/screens/*.jsx` file
side by side and port it function-by-function and JSX-block-by-block,
the same way `HomeView.swift` was built from `Home.jsx`.

## What's actually left — screen by screen

For each: the JS file to port, and what it needs from the app layer
(mostly already built).

Shared form pieces for these screens already exist in
`Components/FormControls.swift` — `QLabel`, `SegGroup`, `Pill`,
`ErrorBox`, `.coachInput()` — each a port of the matching CSS class,
plus `Components/ReadinessBar.swift`. Reuse them rather than restyling.

### Past workout (`src/screens/AddPast.jsx`)
Log a session after the fact: day picker, session type, exercises with
per-mode set rows (`Stats.logMode`), copy-last-of-type, effort + notes.
Needs an `AppState.addPastSession` porting `addPastSession()` in
`src/App.jsx` (PRs vs sessions before that date, history re-sorted).

### Workout (`src/screens/Workout.jsx`) — the big one, 876 lines in JS
Set logging (weight/reps/time/dist/effort-tap), warmup/cooldown
display, exercise swap/rename/remove, add/remove sets, "make it
harder" (calls `Gemini.intensifyWorkout`, already built), superset
badges, plate-math helper. The rest timer needs native equivalents for
each web hack, and they're all *more* reliable natively:
- wake lock → `UIApplication.shared.isIdleTimerDisabled = true`
- rest-over alert → `UNUserNotificationCenter` local notification
  (ask permission once, schedule on rest start, cancel on dismiss)
- vibrate → `UIImpactFeedbackGenerator`
- beep → a short bundled sound via `AVAudioPlayer` or
  `AudioServicesPlaySystemSound`
All the mutating actions (`updateSet`, `swapExercise`, `renameExercise`,
`removeExercise`, `adjustSets`, `applyHarder`) already exist on
`AppState` — this screen is "mostly UI wiring" despite its size.

### Finish (`src/screens/Finish.jsx`)
RPE slider, pain/feedback text fields, PR banner (`Stats.detectPRs` is
already wired into `AppState.finishSession()`). Small screen.

### History / HistoryDetail (`src/screens/History.jsx`, `HistoryDetail.jsx`)
List of past sessions (swipe-to-delete → `AppState.deleteSession`,
already built) and a detail view with a session-scoped coach chat
(`Gemini.askCoach(..., focusSession:)`, already built).

### Records (`src/screens/Records.jsx`)
All-time PRs per exercise — reads `Stats.prRecords` (already built,
currently only exposed via `Stats.detectPRs`; add a small public
wrapper or just call `Stats.prRecords(history)` directly, it's already
internal-not-private).

### Progress (`src/screens/Progress.jsx`)
Charts: use **Swift Charts** (`import Charts`, iOS 16+) for the
line/bar charts — `LineMark`/`BarMark` map directly onto
`src/components/Charts.jsx`'s `LineChart`/`BarChart`. The training
heatmap needs a custom `Canvas`-drawn grid (no direct Swift Charts
equivalent). Data comes from `Stats.exerciseSeries`, `Stats.weeklyBuckets`,
`Stats.muscleBalance` — all already built.

### Settings (`src/screens/Settings.jsx`, 658 lines in JS)
The biggest remaining screen by line count, but it's almost entirely
forms bound to things that already exist: Gemini key (`Keychain.apiKey`),
AI profile/goals/equipment/routine/cue-notes (`LocalStore.shared.
updateAISettings`, already built), GitHub repo+token display
(`GitHubSync.config()`/`setConfig()`), sign out (`Account.signOut()`),
clear history (`AppState.clearHistory()`), send feedback
(`GitHubSync.sendFeedback`, already built), backup export/import
(new: use `.fileExporter`/`.fileImporter` with the `Backup` struct —
`LocalStore.shared.backup` IS the export, feed it straight to
`JSONEncoder`; import via `JSONDecoder` then `LocalStore.shared.
replaceAll(_:)`, already built).

### Coach chat sheet (`src/screens/Coach.jsx`)
A bottom sheet, reachable from most screens via a floating action
button (`AppState.chatOpen`, already exists). Calls `Gemini.askCoach`
(already built) with a running message list.

## Gotchas future work needs to know about

### Lenient decoding is load-bearing, not optional
Swift's synthesized `Decodable` does **not** fall back to a property's
default value when a JSON key is simply missing — it throws. Real data
from the web app is full of partial objects (a quick-cardio `SetLog`
has no `weight`/`reps` keys at all; `AISettings` commonly has only the
one field someone edited; older sessions predate newer fields). Every
model that can arrive from *outside this app* (i.e. everything inside
`Backup`) has a hand-written `init(from:)` using `decodeIfPresent` with
a default — see `Plan.swift`, `SetLog.swift`, `Checkin.swift`,
`AISettings.swift`, `Backup.swift`, `Session.swift` for the pattern.
**If you add a new field to any of these, add it to the custom decoder
too, not just the property declaration** — otherwise it'll compile fine
and then throw at runtime the first time a real backup is missing that
key, which is most of the time. `CoachAppTests/LenientDecodingTests.swift`
has the regression tests that caught this the first time; add to it
when you add fields.

### Every write goes to the shared database — never drop fields
Models decode leniently *and* losslessly: a document remembers the JSON
it was decoded from and, on encode, writes back only the fields whose
typed value changed (`Models/RawPreserving.swift`). Before this
(2026-10-07) two of four real accounts failed to decode at all and
re-encoding dropped every undeclared field. New fields go in the model,
its `init(from:)` (lenient helpers), its `encodeKnown`, and its
`CodingKeys`; `LenientDecodingTests` / `FirestoreCodecTests` show the
pattern.

### Fonts and icons
Both apps use Barlow Condensed (titles, numbers, tracked caps labels)
and Space Grotesk (body text). Here they're bundled as static weights in
`Resources/Fonts/` (registered via `project.yml`'s `UIAppFonts`; Space
Grotesk's OFL licence sits next to it) and reached through
`Theme.head` / `Theme.body` / `Theme.meta` / `Theme.data`. Icons are SF
Symbols; the website uses a bundled subset of Material Symbols instead
(`src/assets/fonts/`). Colors and fonts mirror `src/index.css`'s
`:root` tokens one-for-one — change both together.

### Health data: HealthKit next; the Watch Shortcut meanwhile
Decided 2026-10-07: native HealthKit replaces the Shortcut → GitHub
`health-inbox/` pipeline. Until it ships, both apps drain the inbox
into Firestore (`GitHubSync.consumeHealthInbox`), producing identical
health rows whichever app gets to a file first.

### Distribution: sideload via Xcode, not TestFlight
Also deliberate: no Apple Developer Program enrollment yet, so builds
are signed with a free personal Apple ID and installed straight from
Xcode. That means **builds stop launching after ~7 days** and need
re-signing (open Xcode, plug in the phone, hit Run again — no code
changes needed). If/when this goes to the beta group (Karan/Keshav/
Jake), that's the point to pay for the $99/yr Developer Program and
switch to TestFlight — see `../docs/accounts.md` for how those
accounts are already provisioned on the web side; the invite codes
work unmodified in this app already (tested against a real one).

### The `.xcodeproj` is generated, not hand-edited
`CoachApp.xcodeproj` is produced by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`. **Never hand-edit files/targets in Xcode's project
navigator for anything structural** (new files, new targets, build
settings) — edit `project.yml` and run `xcodegen generate` instead, or
the next regeneration will silently discard the change. Adding a new
`.swift` file under `CoachApp/` needs no project.yml change (XcodeGen
picks up the whole folder); it does need a `xcodegen generate` re-run
before Xcode will see it.

## Dev workflow

```sh
# from ios/CoachApp/
xcodegen generate                                   # after adding files or editing project.yml
xcodebuild -scheme CoachApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -scheme CoachApp \
  -destination 'platform=iOS Simulator,name=iPhone 17'
# UI tests only (CoachAppUITests — drives the real screens on a
# DebugSeed'd install; Home → Check-in → AI error, backdated quick cardio):
xcodebuild test -scheme CoachApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:CoachAppUITests

# see a screen that needs a logged-in account, without a real Google
# sign-in (runs offline — nothing reaches Firestore):
xcrun simctl install <device-udid> <path-to>/CoachApp.app
SIMCTL_CHILD_COACH_DEBUG_SEED=1 xcrun simctl launch <device-udid> com.expdeath.CoachApp
xcrun simctl io <device-udid> screenshot out.png

# boot straight onto a deeper screen (checkIn | generating):
SIMCTL_CHILD_COACH_DEBUG_SEED=1 SIMCTL_CHILD_COACH_DEBUG_SCREEN=checkIn \
  xcrun simctl launch <device-udid> com.expdeath.CoachApp
```

Unit tests without a simulator: the non-UI sources compile for macOS
with a stand-in for `Sync/Cloud.swift` (which needs the iOS Firebase
SDK) and run via XCTest directly — how the suite was run on 2026-10-07
while Xcode 27's simulator component was missing (fix:
`sudo xcodebuild -runFirstLaunch`).

Or just open `CoachApp.xcodeproj` in Xcode and hit Run — see the root
`README.md`'s "step-by-step" instructions for signing onto a real
device with a free Apple ID.

## Immediate next step

Every web screen is ported and the app runs against the shared Firestore
data. Left: verify Apple Health on the real iPhone (Settings → ⌚ Apple
Watch & Health → Connect Apple Health), then turn off the Shortcut
automation once it's confirmed.

iOS-native differences from the web, on purpose: Apple Health is read
directly (HealthKit, de-duplicated across Watch + iPhone); the rest timer
schedules a real local notification (fires with the phone locked); set
ticks and rest-over use haptics; charts use Swift Charts.

Signing: `DEVELOPMENT_TEAM` (free Personal Team) is pinned in project.yml
so regenerating doesn't break device builds. Free-team builds expire
after ~7 days — reinstall with
`xcodebuild -scheme CoachApp -destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates build`
and `xcrun devicectl device install app`. HealthKit works with free
provisioning (verified: the generated profile carries the entitlement).
