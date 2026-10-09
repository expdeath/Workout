// ── COACH server (Firebase Functions, europe-west2) ─────────────────
// coach       — COACH Pro's AI: the apps send the Gemini request they'd
//               otherwise send with their own key; this checks the
//               sign-in, Pro status, AI consent and the daily limit, then
//               forwards it with the owner's key (a secret — never in an app).
// revenuecat  — RevenueCat webhook: any purchase/renewal/expiry event
//               re-reads the subscriber from RevenueCat and writes
//               entitlements/{accountId} (the only writer of it).
// refreshPro  — the same re-read, asked for by the app right after a
//               purchase so Pro switches on without waiting for the webhook.
// Setup + deploy: docs/subscriptions.md.

const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
const REVENUECAT_SECRET_KEY = defineSecret('REVENUECAT_SECRET_KEY');
const REVENUECAT_WEBHOOK_AUTH = defineSecret('REVENUECAT_WEBHOOK_AUTH');

const GEMINI_BASE = process.env.GEMINI_BASE_URL || 'https://generativelanguage.googleapis.com';
const REVENUECAT_BASE = process.env.REVENUECAT_BASE_URL || 'https://api.revenuecat.com';
const REGION = 'europe-west2';
const ORIGINS = [/^https:\/\/expdeath\.github\.io$/, /^http:\/\/localhost(:\d+)?$/];

/** The models the apps use — nothing else goes out on the owner's key. */
const MODELS = new Set(['gemini-3.5-flash', 'gemini-3.1-flash-lite', 'gemini-3.6-flash']);
/** AI requests per account per day (a session plan is 1, a chat reply 1). */
const DAILY_LIMIT = 60;
const MAX_OUTPUT_TOKENS = 8000;
const ENTITLEMENT = 'pro';

const fail = (res, status, message) => res.status(status).json({ error: { code: status, message } });

/** Bearer Firebase ID token → { acct, email } of an allowed account, or throws [status, message]. */
async function accountOf(req) {
  const m = /^Bearer (.+)$/.exec(req.get('Authorization') || '');
  if (!m) throw [401, 'Sign in first.'];
  let tok;
  try {
    tok = await admin.auth().verifyIdToken(m[1]);
  } catch {
    throw [401, 'Your sign-in expired — open the app again.'];
  }
  if (!tok.email || tok.email_verified !== true) throw [401, 'Sign in with a verified email.'];
  const email = tok.email.toLowerCase();
  const entry = await db.doc(`allowlist/${email}`).get();
  if (!entry.exists || entry.get('blocked') === true) throw [403, 'This account is turned off.'];
  return { acct: entry.get('accountId'), email };
}

const proActive = (e) => !!e && e.pro === true && (!e.expiresAt || e.expiresAt > Date.now());

/** Re-read the subscriber from RevenueCat (the source of truth) and store it. */
async function syncEntitlement(acct, why) {
  const r = await fetch(`${REVENUECAT_BASE}/v1/subscribers/${encodeURIComponent(acct)}`, {
    headers: { Authorization: `Bearer ${REVENUECAT_SECRET_KEY.value()}` },
  });
  if (!r.ok) throw new Error(`RevenueCat ${r.status}`);
  const sub = (await r.json()).subscriber || {};
  const ent = sub.entitlements?.[ENTITLEMENT];
  const expiresAt = ent?.expires_date ? Date.parse(ent.expires_date) : null;
  const product = ent?.product_identifier ? sub.subscriptions?.[ent.product_identifier] : null;
  const status = {
    pro: !!ent && (expiresAt === null || expiresAt > Date.now()),
    expiresAt,
    productId: ent?.product_identifier || null,
    store: product?.store || null,
    trial: product?.period_type === 'trial',
    willRenew: product ? !product.unsubscribe_detected_at : false,
    managementUrl: sub.management_url || null,
    updatedAt: Date.now(),
    lastEvent: why,
  };
  await db.doc(`entitlements/${acct}`).set(status);
  return status;
}

exports.coach = onRequest(
  { region: REGION, cors: ORIGINS, secrets: [GEMINI_API_KEY], timeoutSeconds: 90, maxInstances: 20, memory: '256MiB' },
  async (req, res) => {
    if (req.method !== 'POST') return fail(res, 405, 'POST only.');
    let who;
    try {
      who = await accountOf(req);
    } catch ([status, message]) {
      return fail(res, status, message);
    }
    const { acct } = who;
    const [ent, consent] = await Promise.all([
      db.doc(`entitlements/${acct}`).get(),
      db.doc(`accounts/${acct}/state/aiConsent`).get(),
    ]);
    if (!proActive(ent.data())) return fail(res, 402, 'COACH Pro isn’t active on this account.');
    // the same consent the apps ask for (guideline 5.1.2(i)) — checked here too
    if (consent.get('value')?.allowed !== true) return fail(res, 403, 'The AI coach is off — turn it on in Settings → AI Coach.');

    const { model, body } = req.body || {};
    if (!MODELS.has(model) || !body?.contents) return fail(res, 400, 'Unsupported request.');

    // daily limit, counted atomically
    const day = new Date().toISOString().slice(0, 10);
    const usageRef = db.doc(`usage/${acct}_${day}`);
    const count = await db.runTransaction(async (tx) => {
      const n = ((await tx.get(usageRef)).get('count') || 0) + 1;
      tx.set(usageRef, { acct, day, count: n, at: Date.now() });
      return n;
    });
    // 403, not 429: the apps treat 429 as "this model is busy, try another"
    if (count > DAILY_LIMIT) return fail(res, 403, `You've used today's ${DAILY_LIMIT} coach requests — they reset at midnight (UTC).`);

    const cfg = body.generationConfig || {};
    cfg.maxOutputTokens = Math.min(cfg.maxOutputTokens || 2000, MAX_OUTPUT_TOKENS);
    try {
      const r = await fetch(`${GEMINI_BASE}/v1beta/models/${model}:generateContent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-goog-api-key': GEMINI_API_KEY.value() },
        body: JSON.stringify({ ...body, generationConfig: cfg }),
        signal: AbortSignal.timeout(80000),
      });
      // pass Gemini's answer (and its status: 429/503 drive the apps' model fallback) straight back
      res.status(r.status).type('application/json').send(await r.text());
    } catch (e) {
      fail(res, 504, 'The coach timed out — try again.');
    }
  }
);

exports.refreshPro = onRequest(
  { region: REGION, cors: ORIGINS, secrets: [REVENUECAT_SECRET_KEY], maxInstances: 10, memory: '256MiB' },
  async (req, res) => {
    if (req.method !== 'POST') return fail(res, 405, 'POST only.');
    try {
      const { acct } = await accountOf(req);
      res.json(await syncEntitlement(acct, 'refresh'));
    } catch (e) {
      if (Array.isArray(e)) return fail(res, e[0], e[1]);
      fail(res, 502, "Couldn't reach the subscription service — try again.");
    }
  }
);

exports.revenuecat = onRequest(
  { region: REGION, secrets: [REVENUECAT_SECRET_KEY, REVENUECAT_WEBHOOK_AUTH], maxInstances: 10, memory: '256MiB' },
  async (req, res) => {
    if (req.get('Authorization') !== `Bearer ${REVENUECAT_WEBHOOK_AUTH.value()}`) return fail(res, 401, 'Unauthorized.');
    const ev = req.body?.event;
    const acct = ev?.app_user_id;
    // the apps log in to RevenueCat with the COACH account id — anything else isn't ours
    if (!acct || acct.startsWith('$RCAnonymousID')) return res.json({ ok: true, ignored: true });
    try {
      await syncEntitlement(acct, ev.type || 'webhook');
      res.json({ ok: true });
    } catch (e) {
      fail(res, 500, e.message); // RevenueCat retries failed webhooks
    }
  }
);
