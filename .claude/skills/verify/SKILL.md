---
name: verify
description: Build, launch, and drive the COACH app to verify changes at the real UI.
---

# Verifying COACH changes

Surface is a mobile-sized React PWA (Vite). No test suite — verify by
driving the UI headlessly.

## Launch

```bash
npx vite --port 5199 --strictPort --no-open &   # serves http://localhost:5199/
```

Dev server has no CSP (build-only) and base `/` (only GitHub Actions
builds use `/Workout/`).

## Drive

`npm i playwright-core` in the scratchpad and launch with
`chromium.launch({ channel: 'chrome' })` — system Chrome works, no
browser download needed. Use a 390×844 viewport.

Skip the AI/onboarding by seeding localStorage in `addInitScript`:

- `coach:gemini-api-key` — any string, or the app opens on Settings.
- `coach:today` — a session object (`{id: 'YYYY-MM-DD#n', date, plan:
  {sessionType, exercises: [...]}, log: [[{weight,reps,done}...]...],
  finished: false}`) with `date === today` puts a "Resume <type>"
  button on Home → straight into the Workout screen.
- `coach:history` — JSON array of prior sessions; clearing
  `coach:migrated-idb` makes the app migrate it into IndexedDB on boot
  (only when the IDB store is empty).
- `coach:ai-settings` — profile/routine plus gym setup (`barKg`,
  `plates`).

Nav labels: Home header has a gear SVG (settings, first
`.header__actions .ghost-btn`), "Stats" (Progress), "Log" (History).

## Seeding health rows (HRV/RHR/sleep/body weight)

Health data lives in IndexedDB `coach-db` (version 3), store `health`
(keyPath `date`). Boot the app once first (so the DB upgrade runs),
then `page.evaluate` an `indexedDB.open('coach-db', 3)` and `put` rows
like `{ date, hrv, rhr, steps, sleepH, weightKg }`, then `page.reload()`.

To fake the AI, `page.route('**/generativelanguage.googleapis.com/**')`
and fulfill with `{ candidates: [{ content: { parts: [{ text:
JSON.stringify(plan) }] }, finishReason: 'STOP' }] }` — this also lets
you capture and assert on the outgoing prompt.

## Gotchas

- A reload always lands on Home — re-enter the workout via "Resume
  <type>" before asserting on workout-screen elements.
- `text=Discard` matches the confirm's question span before the
  button; click `.remove-confirm__yes` instead.

- Gemini calls fail gracefully with a fake key (debrief/weekly review
  just warn) — fine for UI flows.
- Finishing a session pushes to GitHub sync only if configured;
  unconfigured is a no-op.
- Screens animate in (`screen--slide-in`); screenshot after a
  selector wait, or the frame may be mid-fade.
