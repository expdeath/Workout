# COACH — native Android app

A native Kotlin + Jetpack Compose port of the iPhone app (`ios/CoachApp` on the
`ios` branch),
which is itself a port of the web app (`../src`). Same data (Cloud Firestore,
shared live with the web and iPhone apps), same Google sign-in, same Gemini AI
coach, same prompts. It's a from-scratch port, not a wrapper around the website.
When in doubt about what something should do, the answer is "whatever the
matching Swift file does", and behind that "whatever the matching JS file does".

## Status

| Area | Android file(s) | Ported from |
|---|---|---|
| Data models, lenient + lossless JSON | `models/` | `Models/` |
| Firestore codec (identical documents) | `sync/FirestoreCodec.kt` | `Sync/FirestoreCodec.swift` |
| Firestore + Google sign-in + allowlist | `sync/Cloud.kt`, `account/Account.kt` | `Sync/Cloud.swift`, `Account/Account.swift` |
| GitHub backup + Watch inbox drain | `sync/GitHubSync.kt` | `Sync/GitHubSync.swift` |
| Health data | `sync/HealthConnectSync.kt` | `Sync/HealthKitSync.swift` |
| Stats / progression / dashboard / calories | `stats/` | `Stats/` |
| Gemini client + long-term context | `ai/` | `AI/` |
| COACH Pro (RevenueCat, Google Play) | `account/Subscriptions.kt` | `Account/Subscriptions.swift` |
| Sign in with Apple (built, switched off) | `account/Account.kt` (`AppleSignIn.enabled`) | `Account/AppleSignIn.swift` |
| App state machine | `app/AppState.kt` | `App/AppState.swift` |
| Every screen and sheet | `ui/screens/` | `Screens/` |
| Charts (line, bar, heatmap) | `ui/Charts.kt` (Canvas) | `Components/Charts.swift` (Swift Charts) |
| Rest-timer alerts | `app/RestAlarmReceiver.kt` | `UNUserNotificationCenter` in `WorkoutView.swift` |
| Debug seed (offline screenshots) | `app/DebugSeed.kt` | `App/DebugSeed.swift` |
| Unit tests | `app/src/test/` (JUnit, every iOS unit test ported) | `CoachAppTests/` |

### Android differences, on purpose

- **Health Connect instead of HealthKit.** Same metrics, same per-day rows,
  same "HRVavg(ms): … SleepHrs: …" text. Two differences are forced by the
  platform: HRV is RMSSD (Health Connect has no SDNN), and there is no
  wrist-temperature reading. The watch's own app (Fitbit, Samsung Health,
  Garmin Connect, Pixel Watch…) has to share its data with Health Connect.
- **Credential Manager** for Google sign-in (the Android replacement for the
  Google Sign-In SDK).
- **Rest timer:** an `AlarmManager` alarm posts the "Rest over — GO"
  notification when the app is in the background. Exact alarms need the
  user's OK on Android 14+. Without it the alert can arrive a few seconds
  late. In the app, the rest bar buzzes and beeps itself.
- **COACH Pro** sells through Google Play via RevenueCat. Purchases on any
  store map to the same `pro` entitlement.
- **Share / export** use the Android share sheet. **Import** uses the system
  file picker.

## Setup (one-time)

### 1. Firebase + Google sign-in

The app runs without `google-services.json`: `Cloud.configure()` falls back to
the web app's public Firebase settings. Google sign-in on Android also needs
an **Android OAuth client** in the `heath-9a322` project, matched to the app's
package name and signing-key fingerprint. Without it, Credential Manager
reports a developer-configuration error.

1. Firebase console → Project settings → *Add app* → Android.
   Package name `com.expdeath.coach`.
2. Add the debug signing SHA-1 (this Mac's `~/.android/debug.keystore`):
   `0A:4A:0D:A6:F7:A4:9E:51:B2:DB:76:71:73:2B:6D:DD:48:1F:A3:84`
   (Add the release key's SHA-1 too when there is one:
   `keytool -list -v -keystore <release.jks>`.)
3. Download `google-services.json` into `android/app/`. The build picks it up
   automatically (the plugin is applied only when the file exists).
4. Authentication → Sign-in method → Google must stay enabled. It already is
   for the web app.

`Cloud.WEB_CLIENT_ID` is the project's web OAuth client (the one Firebase's
Google provider uses), so the ID token Credential Manager returns is accepted
by Firebase Auth.

### 2. COACH Pro (optional)

Set `Subscriptions.googleAPIKey` to the RevenueCat public Google key
(`goog_…`). Pro stays off until then, exactly like the iPhone app
(see `../docs/subscriptions.md`).

## Dev workflow

```sh
# from android/
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :app:assembleDebug          # → app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:testDebugUnitTest      # JUnit: models, codec, stats, sync merge, Gemini (stubbed), workouts
```

Or open `android/` in Android Studio and press Run.

See a screen that needs a signed-in account, without a real Google sign-in
(runs offline; nothing reaches Firestore; debug builds only):

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.expdeath.coach/.app.MainActivity \
  --es COACH_DEBUG_SEED 1 --es COACH_DEBUG_SCREEN workout \
  --es COACH_DEBUG_RICH 1 --es COACH_DEBUG_WORKOUTS 1
```

`COACH_DEBUG_SCREEN`: `checkIn | generating | workout | finish | history |
records | progress | settings | workouts`. `COACH_DEBUG_CONSENT=ask` shows the
AI-consent screen first.

## Gotchas (same as iOS)

- **Lenient decoding is load-bearing.** Real synced data omits keys and mixes
  types. Every model decodes with the `lenient*` helpers in
  `models/JSONValue.kt`, which never throw.
- **Never drop fields.** Synced documents remember the JSON they came from
  (`models/RawPreserving.kt`) and write back only what changed. A new field
  goes in the model, its `fromJson`, and its `encodeKnown`/`toJson`.
- **Numbers are doubles**, as in JS. `JSONValue.Num(7.0)` is written to
  Firestore as the integer 7, exactly like the web SDK.
