# COACH on the watch (Apple Watch + Wear OS)

The watch app does only what you'd otherwise take the phone out for between
sets. Planning, check-ins, history and the AI stay on the phone.

| On the wrist | How |
|---|---|
| What's next: exercise, set N of M, superset round | `WatchState.next()`: A1 B1 A2 B2 for supersets, otherwise plan order |
| Weight × reps (or min · km), pre-filled | what you logged → the set before it today → the phone's hint (suggested kg, last time) |
| Change it | Digital Crown / rotating bezel, or − / + |
| **DONE** | logs the set and starts the rest timer |
| Rest | countdown ring, a tap at 10 s to go and at GO, +15s, Skip |
| Effort | easy / good / grind for the set just logged (during the rest) |
| Any exercise | tap its name → the list |
| Finish | list → Finish workout → RPE (crown) → Save |
| Heart rate, time, sets done | top line, live from the watch's own workout session |

The watch also runs a workout session for the whole workout (HKWorkoutSession
on Apple Watch, Health Services + a foreground service on Wear OS). That's
what keeps it awake for the rest-over tap with the wrist down, and it's where
heart rate and energy come from. When the session is **finished** (not
cancelled) and lasted over 5 minutes, the workout is saved to health data:

- **Apple Watch:** HealthKit saves the `HKWorkout` itself. The iPhone's
  HealthKitSync reads the day's exercise minutes and energy back in.
- **Wear OS:** the watch sends a `workout` summary (start, end, energy, heart
  rate samples) to the phone. The phone writes an `ExerciseSessionRecord`,
  `ActiveCaloriesBurnedRecord` and `HeartRateRecord` to Health Connect
  (`HealthConnectSync.saveWatchWorkout`), each only if that write permission
  was granted.

## Design: the phone owns the workout

The watch never edits the session itself. The phone sends a **state**
snapshot whenever today's session or the rest timer changes. The watch sends
back **commands**, and the phone applies them through the same `AppState`
edits a tap on the phone makes (`updateSet`, `adjustSets`, `startRest`,
`finishSession`…). So a set logged on the wrist is validated, saved to
Firestore, backed up and counted for PRs exactly like one typed on the phone.

To stay instant and work out of range, the watch applies its own commands to
the last snapshot straight away (`WatchState.applying`) and keeps them as
*pending*. Every snapshot lists the ids of the last 40 commands the phone
applied (`acks`). The watch shows `phoneState.withPending(pending not acked)`.
Pending commands older than 30 minutes are dropped.

The phone applies each command id once, so redelivery is harmless. A command
for another session (`session` ≠ today's id) does nothing. A command names
its exercise by index *and* name; if the plan changed on the phone, the name
wins.

## Transport

| | iPhone ↔ Apple Watch (WatchConnectivity) | Android ↔ Wear OS (Data Layer) |
|---|---|---|
| state → watch | `updateApplicationContext(["state": json])` + `sendMessage` when reachable | data item `/coach/state`, `json` field, urgent |
| command → phone | `sendMessage(["cmd": json])` when reachable, else `transferUserInfo` (queued) | one data item per command, `/coach/cmd/<id>`, urgent (queued by Play services); the phone deletes it once applied |
| phone app closed | the message wakes it in the background | `WatchListenerService` runs, creating `AppState` if needed |
| open the watch app | `HKHealthStore.startWatchApp(with:)` when a workout is generated (starts the watch's workout session too) | `RemoteActivityHelper` → `coach://workout` |
| capabilities | — | phone `coach_phone`, watch `coach_watch` (`res/values/wear.xml`) |

On Android the phone and watch apps share the application id
`com.expdeath.coach` and must be signed with the same key, or the Data Layer
won't connect them.

## JSON (v1)

Both sides read leniently: a missing or wrong-typed field reads as empty.

```jsonc
// WatchState — phone → watch
{
  "v": 1, "active": true, "finished": false,
  "id": "2026-10-10#1760…", "type": "Push", "title": "Push — strength", "startedAt": 1760…, // ms
  "exercises": [{
    "name": "Bench Press", "mode": "strength",          // strength | cardio | check (Stats.logMode)
    "reps": "6-8", "rpe": "8", "restSec": 120,          // parseRestSeconds(rest)
    "target": "62.5", "last": "60kg×8, 60kg×8", "superset": "",
    "sets": [{ "w": "60", "r": "8", "t": "", "d": "", "done": true, "e": "good",
               "pw": "62.5", "pr": "8", "pt": "" }]     // p* = the phone's greyed hints
  }],
  "rest": { "endsAt": 1760…, "total": 120, "ex": "Bench Press" },   // or null
  "acks": ["…command ids…"], "sentAt": 1760…
}

// WatchCommand — watch → phone
{ "v": 1, "id": "uuid", "at": 1760…, "cmd": "logSet", "session": "<state id>",
  "ex": 0, "name": "Bench Press", "set": 1, "w": "62.5", "r": "8", "t": "", "d": "",
  "effort": "", "sec": 0, "rpe": 0, "workout": { … } }
```

| cmd | phone does |
|---|---|
| `logSet` | `updateSet(… done: true)` with w/r (strength), t/d (cardio) or nothing (check), then starts rest from `at` |
| `undoSet` | `updateSet(… done: false)` |
| `effort` | `updateSet(… effort:)`, only `"" / easy / good / grind` |
| `addSet` | `adjustSets(ex, +1)` |
| `restSkip` / `restAdd` | stop / extend the rest timer (`sec` 5…300) |
| `finish` | `fin.rpe = rpe` (1…10, else 7) → `finishSession()` |
| `sync` | nothing: just replies with the current state |
| `workout` | Android: file the summary in Health Connect |

Rest alerts: a rest started from the watch (`fromWatch`) is the watch's to
announce, so the phone doesn't buzz, beep or notify. While the watch app is
in use (contact in the last 30 min), the phone's own rest notification stays
off the wrist (Android `setLocalOnly`; iOS skips it, since a locked iPhone
mirrors notifications to the Watch).

## Code

| | Android branch | iOS branch |
|---|---|---|
| protocol + watch logic | `android/watchlink/` (`WatchLink.kt`, `WatchLinkTest`) | `ios/CoachApp/Shared/WatchLink.swift` (`WatchLinkTests`) |
| phone side | `app/WatchSync.kt`, `sync/WearBridge.kt` (`WatchSyncTest`) | `Sync/WatchSync.swift` (`WatchSyncTests`) |
| watch app | `android/wear/` | `ios/CoachApp/CoachWatch/` |

When the protocol changes, change both `WatchLink` files and both test files
together. `readsTheSwiftEncoding` / `testReadsTheKotlinEncoding` pin the
cross-platform JSON.

## Debug screenshots without a phone

- Wear OS: `adb shell am start -n com.expdeath.coach/com.expdeath.coach.wear.WatchActivity --es COACH_DEBUG_SEED workout|rest|idle|done`
- Apple Watch: `xcrun simctl launch <watch> com.expdeath.CoachApp.watchkitapp -COACH_DEBUG_SEED workout|rest|idle|done`
  (debug builds only; no Health prompt and no workout session in this mode)
