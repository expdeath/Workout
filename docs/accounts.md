# Beta accounts (invite-only)

There is no signup. You (the owner) provision each account by hand and
send the person one invite code. The code carries their whole setup: a
private GitHub data repo, a token scoped to only that repo, and
(optionally) a Gemini API key. Redeeming it on the login screen
configures the app; their data then syncs to their repo exactly like
yours does.

## Provision a new user (~3 minutes)

1. **Create their data repo** (private, under your account):

   ```sh
   gh api user/repos -f name=coach-data-<name> -F private=true -F auto_init=true
   ```

   (or github.com → New repository → private, init with README)

2. **Create their token**: github.com → Settings → Developer settings →
   Personal access tokens → **Fine-grained tokens** → Generate new token.
   - Token name: `coach-<name>` · Expiration: 1 year
   - Repository access: **Only select repositories** → their repo only
   - Permissions: **Contents → Read and write** (nothing else)

3. **Generate the invite code**:

   ```sh
   node scripts/make-invite.js --name Karan \
     --repo expdeath/coach-data-karan \
     --token github_pat_… \
     --gemini AIzaSy…        # optional: omit to have them use their own key
   ```

   The script verifies the token against the repo before printing.

4. **Send the magic link privately** (WhatsApp/Signal) — the script
   prints it (`…/Workout/#invite=<code>`). Tapping it signs them in
   automatically; the bare code pasted into the login box also works.
   On iPhone: Share → Add to Home Screen makes it a real app.
   A magic link tapped on an already-set-up device is ignored, so it
   can't clobber an existing account.

## Day-to-day

- **Reading their feedback**: Settings → Send feedback commits a file
  into `feedback/` of their data repo. Their training log is the repo's
  README, auto-updated on every sync.
- **Revoking someone**: revoke their PAT (Developer settings → the
  token → Delete). The app shows "token rejected" on their next sync.
  Their local data stays on their phone until they sign out.
- **Token expiry** (max 1 year): make a new PAT for the same repo, run
  the script again, send the fresh code. Redeeming it keeps their data —
  it only overwrites config.

## Notes

- The invite code **is** the credential — treat it like a password.
- One Gemini key across users shares one quota; if someone gets heavy
  usage, move them to their own free key (aistudio.google.com/apikey →
  they paste it in Settings → AI Coach).
