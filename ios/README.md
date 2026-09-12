# COACH — native iOS app

A native SwiftUI rewrite of the COACH web app (`../src`), living in
`ios/CoachApp/`. Same data, same GitHub-backed sync, same Gemini AI
coach — a from-scratch port, not a wrapper around the website. This
file tracks what's actually done, what's left, and exactly what to do
next.

## Status at a glance

| Area | Status |
|---|---|
| Data models (Session/Plan/Backup/etc.) | ✅ Done, tested |
| Local persistence | ✅ Done |
| GitHub sync engine | ✅ Done, tested |
| Training stats / progression math | ✅ Done, tested |
| Gemini AI client | ✅ Done, tested |
| Invite-code auth | ✅ Done, tested |
| Visual theme (colors/fonts matching the website) | ✅ Done (Login, Home) |
| Login screen | ✅ Done |
| Home screen | ✅ Done (quick cardio can be backdated, like the web) |
| CheckIn screen | ✅ Done |
| Generating screen | ✅ Done |
| Past workout screen (`src/screens/AddPast.jsx`) | ❌ Not started |
| Workout screen (rest timer, set logging) | ❌ Not started |
| Finish screen | ❌ Not started |
| History / HistoryDetail screens | ❌ Not started |
| Records screen | ❌ Not started |
| Progress screen (charts) | ❌ Not started |
| Settings screen | ❌ Not started |
| Coach chat sheet | ❌ Not started |
| HealthKit | Deliberately deferred — see "Health data" below |
| App Store / TestFlight distribution | Deliberately deferred — see "Distribution" below |

57 automated tests, all passing (`CoachAppTests/`). Every "done" row
above was verified by building and running in the iOS Simulator here,
not just compiling.

## How this app relates to the website

Same backend, two frontends. Both read/write the exact same
`coach-backup.json` in the user's private GitHub data repo, both
decode the exact same invite-code format from `scripts/make-invite.js`,
both call Gemini directly with the same prompts. **No migration is
needed and none is planned** — an invite code works in either app, and
a session logged in one shows up in the other after a sync. When in
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
      DebugSeed.swift          #if DEBUG-only: seeds a fake account +
                               session via COACH_DEBUG_SEED=1 env var,
                               for screenshotting screens that need a
                               logged-in state without typing a real
                               invite code through UI automation
    Models/                   Codable structs mirroring the exact JSON
                               shapes in src/db/db.js, src/db/sync.js,
                               src/api/gemini.js (PLAN_SCHEMA). Several
                               have hand-written lenient decoders — see
                               "Gotcha: lenient decoding" below.
    Persistence/
      LocalStore.swift        the full app state as one JSON file on
                               disk (Application Support) — ports
                               src/db/db.js's IndexedDB stores
      Keychain.swift           Gemini key + GitHub token (upgrade over
                               the web app's localStorage)
      Defaults.swift            small non-secret settings (UserDefaults)
    Sync/
      GitHubSync.swift        full port of src/db/sync.js: fetch/push,
                               mergeBackups/normalizeBackup, health-inbox
                               drain, feedback, conflict retry
    Stats/
      Stats.swift              full port of src/utils/stats.js
      Helpers.swift            date formatting + set-input clamping,
                               ports src/utils/helpers.js
    AI/
      GeminiClient.swift       full port of src/api/gemini.js
      AIContext.swift          ports src/utils/aiContext.js
    Account/
      Account.swift            invite-code parsing/redeem, ports
                               src/utils/account.js — ALSO accepts a
                               full magic link, not just the bare code
                               (see "Gotcha: invite links" below)
    Screens/                  one SwiftUI view per src/screens/*.jsx
    Components/                one SwiftUI view per src/components/*.jsx
    Resources/Fonts/           bundled Barlow Condensed + IBM Plex Mono
                               .ttf files (see "Gotcha: fonts" below)
  CoachAppTests/               XCTest target, 53 tests
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

### Invite links, not just bare codes
The website has two separate entry paths: `Login.jsx`'s paste box
(expects the bare code) and `App.jsx`'s boot-time URL-hash parsing
(auto-extracts the code from a tapped `#invite=...` magic link). This
app has no URL-scheme entry point, so `Account.parseInviteCode` was
changed to accept *either* form directly — extracting the code out of
a full link if one is pasted. Keep that in mind if the login UI ever
changes.

### Fonts: only 2 of 3 are bundled
The website uses Barlow Condensed (headers), IBM Plex Mono (numbers/
mono UI), and Archivo (body text) — see `src/index.css`'s `@import`.
Only the first two are bundled here (`Resources/Fonts/`, registered via
`Info.plist`'s `UIAppFonts`); body text currently falls back to the
system font (San Francisco). Archivo only ships as a variable font
(`Archivo[wdth,wght].ttf`) upstream, which complicates per-weight
`Font.custom(...)` lookups — worth doing properly if/when visual
fidelity on body text matters, but San Francisco reads close enough
that it wasn't blocking.

### Health data: Watch Shortcut pipeline, not HealthKit
Deliberate scope call, not a gap to "fix": this app drains the same
`health-inbox/` GitHub folder the existing Watch Shortcut already
writes to (`GitHubSync.consumeHealthInbox`, already built and tested),
rather than reading HealthKit directly. Native HealthKit integration
is a real future upgrade, but was explicitly decided against for v1 to
avoid blocking the whole rewrite on new permissions/entitlements work.
Revisit once the core loop is fully shipped.

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

# see a screen that needs a logged-in account, without typing a real
# invite code:
xcrun simctl install <device-udid> <path-to>/CoachApp.app
SIMCTL_CHILD_COACH_DEBUG_SEED=1 xcrun simctl launch <device-udid> com.expdeath.CoachApp
xcrun simctl io <device-udid> screenshot out.png

# boot straight onto a deeper screen (checkIn | generating):
SIMCTL_CHILD_COACH_DEBUG_SEED=1 SIMCTL_CHILD_COACH_DEBUG_SCREEN=checkIn \
  xcrun simctl launch <device-udid> com.expdeath.CoachApp
```

Or just open `CoachApp.xcodeproj` in Xcode and hit Run — see the root
`README.md`'s "step-by-step" instructions for signing onto a real
device with a free Apple ID.

## Immediate next step

Build `WorkoutView` next, then `FinishView` — Home → CheckIn →
Generating already works end to end against the real Gemini client, so
those two close the daily loop (Workout → Finish). Port
`src/screens/Workout.jsx` directly, following the same pattern
`CheckInView.swift` used for `CheckIn.jsx`.
