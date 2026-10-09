# Releasing COACH on the App Store

What the app already does for App Review, and the steps that need you
(the paid developer account, consoles, the store listing).

## Done in the code

| Requirement | Where |
|---|---|
| **4.8 Login services** — a privacy-friendly option next to Google | Sign in with Apple: `Account/AppleSignIn.swift`, `Cloud.signInWithApple`, Login button. **Built but switched off** until the steps below. |
| **5.1.1(v) Account deletion** in the app | Settings → Delete account (iOS + web). Re-confirms the sign-in, deletes every document of the account, the account, the allowlist entry and the Firebase sign-in; an Apple sign-in's token is revoked. Rules: `firestore.rules`. |
| **5.1.2(i) Consent before sharing with third-party AI** | First launch asks before anything goes to Google Gemini (`AIConsentView.swift`, `src/screens/AIConsent.jsx`). Every Gemini request checks it (`Gemini.post`, `requireAIConsent`). Settings → AI Coach turns it on/off. Account state `aiConsent`. |
| **Export compliance** | `ITSAppUsesNonExemptEncryption = NO` in Info.plist |
| **Privacy manifest** | `ios/CoachApp/CoachApp/PrivacyInfo.xcprivacy` — UserDefaults (reason CA92.1), no tracking, the collected data types. |

## Your steps

### 1. Apple Developer Program
Join at developer.apple.com/programs ($99/year). Then in
`ios/CoachApp/project.yml` replace `DEVELOPMENT_TEAM: WFR2GPT97L`
(the free Personal Team) with the new team ID.

### 2. Switch on Sign in with Apple
1. `project.yml`: uncomment `com.apple.developer.applesignin: [Default]`
   and the `SWIFT_ACTIVE_COMPILATION_CONDITIONS … APPLE_SIGN_IN` line,
   then `xcodegen generate`.
2. developer.apple.com → Identifiers → `com.expdeath.CoachApp` → enable
   *Sign in with Apple*.
3. For the website and for token revocation: create a **Services ID**
   (e.g. `com.expdeath.coach.web`), set its return URL to
   `https://heath-9a322.firebaseapp.com/__/auth/handler`, and create a
   **Sign in with Apple key** (download the .p8 once).
4. Firebase console → Authentication → Sign-in method → **Apple** →
   enable; fill in the Services ID, Team ID, Key ID and private key.
5. Website: set `APPLE_SIGN_IN = true` in `src/db/cloud.js`.

The same person signing in with Apple and with Google gets two separate
accounts (different emails, often a private-relay one from Apple).

### 3. Firestore rules
Paste the current `firestore.rules` into Firebase console → Firestore →
Rules → Publish. Account deletion needs them.

### 4. Privacy policy
A public page (it can be a GitHub Pages file) covering:
- what's stored in Firebase/Firestore: account email and name, workouts,
  check-ins, Apple Health readings, coach chats, saved workouts, settings;
- that Apple Health data and the rest go to **Google Gemini** only after
  the in-app consent, with the user's own Gemini key, under Google's terms;
- the optional GitHub backup to the user's own repository;
- that the app owner (admin) can read accounts' data;
- how to delete everything: Settings → Delete account.

### 5. App Store Connect
- **App Privacy** answers matching the manifest: Contact info (email,
  name), Health & Fitness, User ID, Photos, User Content, Product
  Interaction — all *linked to the user*, *not used for tracking*,
  purpose *App Functionality*.
- **Review notes**: a demo Google account with a working Gemini key and
  a few logged sessions, and a note that the AI coach needs the user's
  own free Gemini API key (Settings → AI Coach).
- Screenshots (6.9" and 6.5" iPhone), description, keywords, support
  URL, privacy policy URL, age rating.
- Export compliance is answered in the app already
  (`ITSAppUsesNonExemptEncryption = NO`: standard HTTPS only).

### Worth deciding before launch
- **Gemini key**: new users must make their own key at
  aistudio.google.com. A server that holds one key would be smoother but
  needs the paid Firebase plan and costs per use.
- **Firebase plan**: the free plan caps reads at 50,000/day across all
  users; each app launch reads the account's whole history. Move to the
  pay-as-you-go plan before a public launch.
