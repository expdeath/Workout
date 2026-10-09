# COACH Pro — setup

COACH Pro ($4.99/month, 7-day free trial) runs the AI coach on COACH's
server with your Gemini key, so subscribers don't need a key of their
own. Everything else stays free, including the AI with a user's own key.

## How it fits together

```
iPhone ── App Store purchase ──┐                    ┌── entitlements/{accountId}
                               ├── RevenueCat ── webhook ──▶ functions: revenuecat ─┤   (written only by the server)
Website ── Stripe checkout ────┘                    └── refreshPro (right after a purchase)

App/website ── AI request + sign-in token ──▶ functions: coach ── checks Pro, consent, daily limit ──▶ Gemini (your key)
```

- **Server**: `functions/index.js` (Firebase Functions, London `europe-west2`).
  `coach` forwards AI requests (only the app's own models, output capped,
  60 a day per account); `revenuecat` is the webhook; `refreshPro` is
  called by the apps after a purchase. Tested in the emulator.
- **Apps**: an account with active Pro sends every AI request to `coach`
  with its sign-in token instead of calling Google with a key
  (`geminiFetch` in `src/api/gemini.js`, `Gemini.post` on iOS). Pro is read
  from `entitlements/{accountId}`, which the database rules let only the
  server write.
- **Purchases**: RevenueCat, customer ID = the COACH account ID, one
  entitlement `pro` for both stores. iOS: `Account/Subscriptions.swift`,
  `Screens/ProView.swift`. Web: `src/screens/Pro.jsx`
  (`@revenuecat/purchases-js`, loaded only at checkout).
- **Switched off** until the keys below are filled in: the website and the
  app show “Coming soon”.

## Your steps

### 1. Firebase pay-as-you-go plan
Firebase console → Usage and billing → upgrade project `heath-9a322` to
**Blaze**. Functions need it, and it lifts the 50,000 reads/day cap.
Set a budget alert (Google Cloud → Billing → Budgets) — e.g. $20/month.

### 2. A paid Gemini key for the server
In Google AI Studio, create a key in a project **with billing enabled**
(paid tier: Google doesn't use the requests to improve its products —
the privacy policy promises this). Keep it out of the apps.

### 3. RevenueCat
1. Create a RevenueCat project “COACH”.
2. **App Store** (needs the Apple Developer Program): in App Store Connect
   sign the Paid Apps agreement, add banking and tax, and join the App
   Store Small Business Program (15% commission instead of 30%). Create a
   subscription group “COACH Pro” with product `coach_pro_monthly`,
   $4.99/month, introductory offer **1 week free**. Connect the app to
   RevenueCat (bundle ID `com.expdeath.CoachApp`, In-App Purchase key).
3. **Web Billing**: connect your Stripe account in RevenueCat → Web
   Billing; create a product at $4.99/month with a 7-day trial.
4. Entitlement **`pro`** → attach both products. Offering **`default`** →
   a monthly package with both.
5. Integrations → **Webhooks**: URL
   `https://europe-west2-heath-9a322.cloudfunctions.net/revenuecat`,
   Authorization header `Bearer <a long random string you make up>`.
6. Copy the keys: the **secret** API key (`sk_…`), the **Apple** public key
   (`appl_…`) and the **Web Billing** public key (`rcb_…`).

### 4. Put the keys in place
Secrets (server only — never in the apps):
```sh
npx firebase-tools login
npx firebase-tools functions:secrets:set GEMINI_API_KEY          # step 2
npx firebase-tools functions:secrets:set REVENUECAT_SECRET_KEY   # sk_…
npx firebase-tools functions:secrets:set REVENUECAT_WEBHOOK_AUTH # the random string, without "Bearer "
```
Public keys (safe in the apps):
- `src/db/cloud.js` → `REVENUECAT_WEB_KEY = 'rcb_…'`
- `ios/CoachApp/CoachApp/Account/Subscriptions.swift` → `appleAPIKey = "appl_…"`

### 5. Deploy
```sh
npx firebase-tools deploy --only functions,firestore:rules
```
(from the repo root — `firebase.json` and `.firebaserc` are set up). Then
push the website and build the app as usual.

### 6. Test before going live
Use Stripe test mode and App Store sandbox testers: buy, check that
Settings shows “Pro · free trial”, plan a session with no key, cancel,
let it expire, restore on iPhone.

## Costs to expect
- Gemini: a session plan is a few thousand tokens — roughly a cent or
  less per request on Flash models; the 60/day limit caps the worst case.
- Firebase Functions: free allowance covers millions of calls/month.
- Apple keeps 15% (Small Business Program), Stripe ~2.9% + 30¢,
  RevenueCat is free until $2.5k/month in revenue.
