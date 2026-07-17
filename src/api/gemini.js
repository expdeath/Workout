// ── Gemini API integration ───────────────────────────────────────
import { parsePlan } from '../utils/parser.js';
import { getApiKey, getAISettings } from '../utils/storage.js';
import { todayStr, setLogged } from '../utils/helpers.js';
import { buildLongTermSummary } from '../utils/aiContext.js';
import {
  progressionTargets,
  healthBaseline,
  parseHealthNumbers,
  deloadSignal,
  fatigueSignal,
  lastPerformance,
  healthTrend,
  muscleGapNote,
} from '../utils/stats.js';
import { logEvent, getAllHealth } from '../db/db.js';

// ── Workout database ─────────────────────────────────────────────
const WORKOUT_DB = `
PUSH DAY — Warm-up: 15min Stairmaster OR chest press warm-up sets.
1. Flat Dumbbell Press 3x10-12 (alt: Seated Chest Press Machine)
2. Incline Dumbbell Press 3x10-12 (alt: Low-to-High Cable Fly)
3. Machine Shoulder Press 3x10-12
4. Cable Lateral Raise 3x12-15
5. Rope Tricep Pushdown 3x12-15
Cooldown: doorway chest stretch, overhead tricep stretch.

PULL DAY — Warm-up: 15min stationary bike.
1. Chest Supported Row 3x8-10
2. Lat Pulldown 3x8-10
3. Machine Rear Delt Fly 3x12-15
4. Cable Curl 3x10-12
Cooldown: lat stretch, bicep stretch.

LEG DAY — Warm-up: 15min stationary bike.
1. Leg Press 3x10-12
2. Seated Leg Curl 3x10-12
3. Leg Extension 3x12-15
4. Calf Press 3x15
Cooldown: quad stretch, hamstring stretch.

ACTIVE RECOVERY — Option 1: 30min stationary bike zone 2.
Option 2: 3 rounds — dead bugs x10/side, bird dog x10/side, plank 45s, side plank 30s/side, hollow hold 20-30s.

CARDIO DAY — Option 1: 35-45min zone 2 — stationary bike, incline treadmill walk, or stairmaster.
Option 2: intervals — 10min easy bike, then 8 × (1min hard / 2min easy), 5min cooldown walk.
Finish: 5min full-body stretch.

STRETCH & MOBILITY DAY — 10min easy bike, then 2 rounds: cat-cow x10, world's greatest stretch x5/side, 90/90 hip switches x10/side, couch stretch 45s/side, hamstring floss x10/side, thoracic wall opener 45s/side, doorway chest stretch 45s/side, deep squat hold 30s.

FULL BODY MIX (fun day) — pick 5-6, 2 sets each, moderate load, superset pairs, 60s rests: leg press, chest press machine, chest supported row, cable lateral raise, cable curl, rope pushdown, plank 45s.
`;

// ── Coaching system prompt ───────────────────────────────────────
// The personal profile is user-editable in Settings (kept out of the
// public repo); this neutral default applies until one is saved.
const DEFAULT_PROFILE =
  'Recreational lifter, trains Push/Pull/Legs at a commercial gym. Goals: strength, muscle, sustainable habits. Sessions 45-75 min, 4-5 per week.';

function coachRules() {
  const profile = (getAISettings().profile || '').trim() || DEFAULT_PROFILE;
  return `You are this person's long-term strength coach. PROFILE: ${profile}
Don't prohibit exercises; prefer supported/machine variations when appropriate, add technique cues. Adapt to today's check-in (soreness, tightness, energy).
Progression: recommend small weight increases, extra reps, or holding, based on logged history. NEVER increase load if recovery looks poor. If returning from 1+ week break: reduce volume, avoid failure, reduce weights, expect DOMS.
Logged sets may carry the athlete's own effort tag — (easy) = clear room to progress, (good) = about right, (grind) = near-failure. Never add load to a lift whose last sets were grinds; treat all-easy sets as a green light for a bigger jump.
Rotate exercises sensibly, avoid repeating identical sessions, keep the split balanced based on the history provided. Do not invent history that isn't in the log.
VARIETY: training is NOT a rigid Push/Pull/Legs loop. Read the history — after 3+ consecutive lifting days, or when no cardio or mobility day appears in the last 7-10 days, schedule a Cardio or Stretch & Mobility day (recovery quality decides which). A Full Body mix day is a good occasional change of pace. If the check-in states a session preference, honor it — it overrides the rotation. Use the LONG-TERM TRAINING SUMMARY for progression decisions and split balance; the recent TRAINING LOG shows exact numbers for the last sessions.
Be direct and analytical. No hype. State uncertainty when the data is thin.`;
}

// ── JSON schema spec sent to the model ──────────────────────────
const JSON_SPEC = `Respond with ONLY minified valid JSON — no markdown fences, no preamble, no trailing text. BE EXTREMELY CONCISE in every string; total response must stay under 900 tokens. Schema:
{"sessionType":"Push|Pull|Legs|Full Body|Cardio|Stretch & Mobility|Active Recovery|Rest Day",
"title":"max 6 words",
"recoveryScore":0-100,
"reasoning":"max 2 short sentences",
"warmup":["max 3 items, max 8 words each"],
"exercises":[{"name":"","sets":3,"reps":"10-12","rpe":"7-8","rest":"90s","notes":"max 10 words or empty","alt":"max 5 words or empty","suggestedWeight":"e.g. 24kg or empty","superset":"A/B or empty"}],
"cardio":{"desc":"max 8 words","duration":"e.g. 15min"} or null,
"cooldown":["max 3 items, max 6 words each"],
"estTimeMin":number including 24min walking,
"concerns":"max 12 words or empty"}
Max 6 exercises. If Rest Day, exercises=[]. For Cardio, Stretch & Mobility, or Active Recovery put the circuit/intervals/stretches in exercises (sets=rounds, reps=duration or count, weight empty).
Supersets: when time is tight or two accessories pair well (non-competing muscles), give BOTH exercises the same "superset" letter and place them adjacently — the athlete alternates sets and shares the rest. Never superset heavy compounds.`;

// Enforced at the API level — malformed/truncated JSON can't happen
const PLAN_SCHEMA = {
  type: 'OBJECT',
  properties: {
    sessionType: { type: 'STRING' },
    title: { type: 'STRING' },
    recoveryScore: { type: 'INTEGER' },
    reasoning: { type: 'STRING' },
    warmup: { type: 'ARRAY', items: { type: 'STRING' } },
    exercises: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          sets: { type: 'INTEGER' },
          reps: { type: 'STRING' },
          rpe: { type: 'STRING' },
          rest: { type: 'STRING' },
          notes: { type: 'STRING' },
          alt: { type: 'STRING' },
          suggestedWeight: { type: 'STRING' },
          superset: { type: 'STRING' },
        },
        required: ['name', 'sets', 'reps'],
      },
    },
    cardio: {
      type: 'OBJECT',
      nullable: true,
      properties: { desc: { type: 'STRING' }, duration: { type: 'STRING' } },
    },
    cooldown: { type: 'ARRAY', items: { type: 'STRING' } },
    estTimeMin: { type: 'INTEGER' },
    concerns: { type: 'STRING' },
  },
  required: ['sessionType', 'exercises', 'estTimeMin'],
};

/**
 * Deterministic guardrails on the model's plan: suggested weights stay
 * within a plausible jump from logged history, session fits the time.
 */
function capSuggestedWeight(ex, history) {
  const m = /([\d.]+)/.exec(String(ex.suggestedWeight || ''));
  if (!m) return false;
  const w = parseFloat(m[1]);
  const lp = lastPerformance(history, ex.name);
  const lastW = lp
    ? Math.max(...lp.sets.map((s) => parseFloat(s.weight)).filter((n) => !Number.isNaN(n)), 0)
    : 0;
  const cap = lastW ? Math.min(Math.max(lastW * 1.15, lastW + 2.5), 200) : 200;
  if (w <= cap) return false;
  ex.suggestedWeight = `${Math.round((cap / 2.5)) * 2.5}kg`;
  return true;
}

export function sanitizePlan(plan, history, checkin) {
  let changed = false;
  if ((plan.exercises || []).length > 6) {
    plan.exercises = plan.exercises.slice(0, 6);
    changed = true;
  }
  for (const ex of plan.exercises || []) {
    if (capSuggestedWeight(ex, history)) changed = true;
  }
  const avail = parseInt(checkin?.timeAvail, 10) || 60;
  if (plan.estTimeMin > avail + 24 + 10) {
    plan.estTimeMin = avail + 24;
    changed = true;
  }
  if (changed) logEvent('plan_sanitized', { sessionType: plan.sessionType });
  return plan;
}

/**
 * Build the user message from check-in data and history.
 */
// Check-in "today's vibe" → an instruction the model must honor
const WISH = {
  lift: 'The athlete wants to LIFT today — pick the right strength session for the split balance.',
  cardio: 'The athlete asked for a CARDIO day — build it around conditioning (bike/stairs/incline walk/intervals), no lifting session.',
  stretch: 'The athlete asked for a STRETCH & MOBILITY day — a full mobility/flexibility session, no heavy lifting.',
  surprise: 'The athlete asked you to SURPRISE them — build something genuinely different from the recent sessions (mixed circuit, superset full-body, conditioning + core, new variations). Keep it safe and equipment-realistic, but make it fun.',
};

function buildUserMessage(checkin, history, healthLog = []) {
  const recent = history.slice(-6);
  const histText = recent.length
    ? recent
        .map(
          (h) =>
            `${h.date} — ${h.plan.sessionType}: ` +
            (h.plan.exercises || [])
              .map((ex, i) => {
                const sets = (h.log?.[i] || [])
                  .filter(setLogged)
                  .map((s) => `${s.weight || '?'}x${s.reps || '?'}${s.effort ? `(${s.effort})` : ''}`)
                  .join(', ');
                return `${ex.name} [${sets || 'no sets logged'}]`;
              })
              .join('; ') +
            (h.finished
              ? ` | session RPE ${h.fin?.rpe ?? '?'}${h.durationMin ? ` | took ${h.durationMin}min` : ''}${h.fin?.pain ? ' | pain: ' + h.fin.pain : ''}${h.fin?.feedback ? ' | notes: ' + h.fin.feedback : ''}`
              : ' | NOT COMPLETED')
        )
        .join('\n')
    : 'No logged sessions yet in this app. Treat as a fresh start — use the base workout database, moderate volume, and ask nothing (choose sensibly).';

  const daysSince = recent.length
    ? Math.round(
        (new Date(todayStr()) - new Date(recent[recent.length - 1].date)) /
          86400000
      )
    : null;

  return `
TODAY: ${todayStr()} (${new Date().toLocaleDateString(undefined, { weekday: 'long' })})

CHECK-IN:
- Energy: ${checkin.energy}/10
- Sleep last night: ${checkin.sleep}
- Soreness: ${checkin.soreness}${checkin.soreAreas ? ' (' + checkin.soreAreas + ')' : ''}
- Lower back tight today: ${checkin.backTight ? 'YES — adapt exercise selection' : 'no'}
- Time available today (gym time, walking excluded): ${checkin.timeAvail} min
${WISH[checkin.wish] ? '- SESSION PREFERENCE (honor this): ' + WISH[checkin.wish] : ''}
${parseFloat(checkin.bodyKg) ? `- Body weight today: ${checkin.bodyKg}kg` : ''}
${checkin.notes ? '- Other notes: ' + checkin.notes : ''}

APPLE HEALTH DATA (pasted by user, may be empty):
${checkin.health || 'None provided today — rely on check-in + history.'}
${(() => {
  const t = healthTrend(healthLog);
  return t ? `WATCH DATA TREND (daily, most recent last):\n${t}` : '';
})()}
${(() => {
  if (!checkin.health) return '';
  const today = parseHealthNumbers(checkin.health);
  const base = healthBaseline(history, healthLog);
  const lines = [];
  if (today.hrv && base.hrv) {
    const d = Math.round(((today.hrv - base.hrv) / base.hrv) * 100);
    lines.push(`HRV ${today.hrv} vs 30-day avg ${base.hrv} (${d >= 0 ? '+' : ''}${d}%)${d <= -10 ? ' — recovery below normal' : ''}`);
  }
  if (today.rhr && base.rhr) {
    const d = Math.round(((today.rhr - base.rhr) / base.rhr) * 100);
    lines.push(`RHR ${today.rhr} vs 30-day avg ${base.rhr} (${d >= 0 ? '+' : ''}${d}%)${d >= 7 ? ' — elevated, possible fatigue/illness' : ''}`);
  }
  return lines.length ? 'Baseline comparison (computed): ' + lines.join('; ') : '';
})()}
${(() => {
  const d = deloadSignal(history);
  return d ? `\nDELOAD WATCH (computed): ${d.reason} Honor this unless today's readiness is clearly excellent.` : '';
})()}
${(() => { const m = muscleGapNote(history); return m ? `\n${m}` : ''; })()}
${(() => {
  const g = (getAISettings().goals || '').trim();
  return g ? `\nATHLETE'S STATED GOALS (steer selection and progression toward these):\n${g}` : '';
})()}
${(() => {
  const cues = getAISettings().cueNotes || {};
  const lines = Object.entries(cues).slice(0, 15).map(([n, t]) => `- ${n}: ${t}`);
  return lines.length
    ? `\nATHLETE'S OWN EXERCISE NOTES (persistent cue cards — respect them when picking/prescribing):\n${lines.join('\n')}`
    : '';
})()}

PROGRESSION TARGETS (computed deterministically from the logs — anchor suggestedWeight on these):
${progressionTargets(history) || 'No logged sets yet.'}

LONG-TERM TRAINING SUMMARY (compressed from full history):
${buildLongTermSummary(history) || 'Not enough history yet — rely on the recent log below.'}

TRAINING LOG (last sessions in detail, most recent last):
${histText}
${daysSince !== null ? `Days since last logged session: ${daysSince}${daysSince >= 7 ? ' — RETURNING FROM BREAK, apply reduced-volume rules.' : ''}` : ''}
${recent.length && recent[recent.length - 1].debrief ? `\nYOUR OWN COACHING NOTE AFTER THE LAST SESSION (follow through on it): ${recent[recent.length - 1].debrief}` : ''}

BASE WORKOUT DATABASE:
${(getAISettings().routine || '').trim() || WORKOUT_DB}

Decide the right session for today and build it. ${JSON_SPEC}`;
}

// Models to try in order — if one is overloaded, try the next.
// 3.5 Flash is the strongest free-tier model (mid-2026); the lite
// and 2.5 fallbacks have higher rate limits if it's busy.
const MODELS = [
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
  'gemini-2.5-flash',
];

/**
 * Call Google Gemini API to generate a workout plan.
 */
async function callGemini(checkin, history, model = MODELS[0], healthLog = []) {
  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error('No Gemini API key set. Go to Settings to add one.');
  }

  const userMsg = buildUserMessage(checkin, history, healthLog);

  // 60-second timeout for the API call
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 60000);

  const startedAt = Date.now();
  logEvent('ai_request', { model });

  let response;
  try {
    console.log(`[COACH] Calling Gemini API (model: ${model})...`);
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          system_instruction: {
            parts: [{ text: coachRules() }],
          },
          contents: [
            {
              role: 'user',
              parts: [{ text: userMsg }],
            },
          ],
          generationConfig: {
            maxOutputTokens: 4000,
            // steadier progression decisions — but let "surprise me" be creative
            temperature: checkin.wish === 'surprise' ? 0.9 : 0.5,
            responseMimeType: 'application/json',
            responseSchema: PLAN_SCHEMA,
            // "low" buys planning quality without the medium-default
            // token burn that used to truncate responses
            ...(model.startsWith('gemini-3.5')
              ? { thinkingConfig: { thinkingLevel: 'low' } }
              : {}),
          },
        }),
      }
    );
    console.log('[COACH] Got response:', response.status);
  } catch (fetchErr) {
    clearTimeout(timeout);
    logEvent('ai_error', { model, kind: fetchErr.name, message: fetchErr.message });
    if (fetchErr.name === 'AbortError') {
      throw new Error('Request timed out after 60 seconds. The AI might be overloaded — try again.');
    }
    throw new Error(`Network error: ${fetchErr.message}`);
  }
  clearTimeout(timeout);

  if (!response.ok) {
    logEvent('ai_error', { model, status: response.status, latencyMs: Date.now() - startedAt });
  }

  // Handle rate limiting
  if (response.status === 429) {
    let errData;
    try {
      errData = await response.json();
    } catch {
      errData = {};
    }
    const msg = errData?.error?.message || '';

    // Detect permanent quota block (limit: 0 = key is blocked or free tier exhausted)
    if (msg.includes('limit: 0')) {
      throw new Error(
        'Your API key has no quota (limit: 0). This usually means your key is an old standard key that Google has blocked since June 2026. ' +
        'Go to aistudio.google.com → API Keys → Create a NEW API key (it will be an auth key automatically). Then paste it in Settings.'
      );
    }

    // Temporary rate limit — extract retry delay
    let retryDelay = 45;
    const match = msg.match(/retry in ([\d.]+)s/i);
    if (match) retryDelay = Math.ceil(parseFloat(match[1]));
    retryDelay = Math.min(retryDelay, 90);

    const err = new Error(`RATE_LIMIT:${retryDelay}`);
    err.retryDelay = retryDelay;
    throw err;
  }

  // Handle 503 overloaded — mark for model fallback
  if (response.status === 503) {
    const err = new Error(`MODEL_OVERLOADED:${model}`);
    err.overloaded = true;
    throw err;
  }

  if (!response.ok) {
    let errMsg;
    try {
      const errData = await response.json();
      errMsg = errData?.error?.message || JSON.stringify(errData);
    } catch {
      errMsg = await response.text().catch(() => 'Unknown error');
    }
    throw new Error(`Gemini API error (${response.status}): ${errMsg}`);
  }

  const data = await response.json();

  // Check if the response was blocked by safety filters
  if (data.promptFeedback?.blockReason) {
    throw new Error(`Request blocked by Gemini: ${data.promptFeedback.blockReason}`);
  }

  const candidate = data.candidates?.[0];
  if (!candidate) {
    throw new Error('No candidates in Gemini response — the request may have been filtered.');
  }

  if (candidate.finishReason === 'SAFETY') {
    throw new Error('Response blocked by Gemini safety filters. Try again.');
  }

  // Extract text from Gemini response
  const text = candidate.content?.parts
    ?.filter((p) => p.text)
    .map((p) => p.text)
    .join('\n');

  if (!text) {
    throw new Error(`Empty response from Gemini. Finish reason: ${candidate.finishReason || 'unknown'}`);
  }

  logEvent('ai_response', {
    model,
    status: response.status,
    latencyMs: Date.now() - startedAt,
    chars: text.length,
    raw: text,
  });

  return sanitizePlan(parsePlan(text), history, checkin);
}

/**
 * Sleep helper
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── Small plain-text calls (debrief, weekly review) ──────────────
// Non-critical: single attempt + one model fallback, 20s timeout.

async function callGeminiText(userMsg, maxTokens, eventType) {
  const apiKey = getApiKey();
  if (!apiKey) throw new Error('No API key');

  let lastErr;
  for (const model of MODELS.slice(0, 2)) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    const startedAt = Date.now();
    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            'X-goog-api-key': apiKey,
          },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: coachRules() }] },
            contents: [{ role: 'user', parts: [{ text: userMsg }] }],
            generationConfig: {
              maxOutputTokens: maxTokens + 1000, // headroom for thinking models
              temperature: 0.6,
              ...(model.startsWith('gemini-3.5')
                ? { thinkingConfig: { thinkingLevel: 'minimal' } }
                : {}),
            },
          }),
        }
      );
      clearTimeout(timeout);
      if (!response.ok) throw new Error(`status ${response.status}`);
      const data = await response.json();
      const text = data.candidates?.[0]?.content?.parts
        ?.filter((p) => p.text)
        .map((p) => p.text)
        .join(' ')
        .trim();
      if (!text) throw new Error('empty response');
      logEvent(eventType, { model, latencyMs: Date.now() - startedAt, raw: text });
      return text;
    } catch (e) {
      clearTimeout(timeout);
      lastErr = e;
    }
  }
  throw lastErr;
}

// One logged session flattened for the chat context — exercises with
// their logged sets, plus how the athlete rated and debriefed it.
function sessionDetail(s) {
  const lines = (s.plan?.exercises || []).map((ex, i) => {
    const sets = (s.log?.[i] || [])
      .filter((x) => x.done || x.weight || x.reps)
      .map((x) => `${x.weight || '?'}×${x.reps || '?'}`)
      .join(' ');
    return `${ex.name}: ${sets || '—'}`;
  });
  return [
    `${s.date} ${s.plan?.sessionType || ''}${s.durationMin ? ` · ${s.durationMin}min` : ''}`,
    ...lines,
    s.fin
      ? `RPE ${s.fin.rpe}/10${s.fin.pain ? ` · pain: ${s.fin.pain}` : ''}${s.fin.feedback ? ` · feedback: ${s.fin.feedback}` : ''}`
      : '',
    s.debrief ? `Debrief already given: ${s.debrief}` : '',
  ].filter(Boolean).join('\n');
}

/**
 * Multi-turn "ask the coach" chat. messages: [{ role: 'user'|'coach', text }].
 * Pass focusSession to scope the chat to one logged session (History detail).
 * Returns the coach's reply as plain text.
 */
export async function askCoach(messages, { history = [], todayPlan = null, healthLog = [], focusSession = null } = {}) {
  const apiKey = getApiKey();
  if (!apiKey) throw new Error('No Gemini API key set — add it in Settings.');

  const recent = history
    .slice(-3)
    .map((h) => `${h.date} ${h.plan?.sessionType} RPE ${h.fin?.rpe ?? '?'}${h.fin?.pain ? ' pain: ' + h.fin.pain : ''}`)
    .join('; ');
  const plan = todayPlan?.plan
    ? `${todayPlan.plan.sessionType} — ${(todayPlan.plan.exercises || []).map((e) => e.name).join(', ')}${todayPlan.finished ? ' (finished)' : ' (in progress)'}`
    : 'none generated yet';
  const trend = healthTrend(healthLog, 4);

  const system = `${coachRules()}
You are now CHATTING with the athlete (often mid-workout, phone in hand). Answer in 2-5 short sentences, plain text, no markdown, immediately practical. If they mention pain, be conservative and suggest the safe variation.
CONTEXT — today's session: ${plan}. Recent: ${recent || 'no logged sessions'}.${trend ? `\nWatch data:\n${trend}` : ''}${focusSession ? `\nFOCUS — the athlete is viewing this logged session and asking about it:\n${sessionDetail(focusSession)}` : ''}`;

  const contents = messages.slice(-12).map((m) => ({
    role: m.role === 'user' ? 'user' : 'model',
    parts: [{ text: m.text }],
  }));

  let lastErr;
  for (const model of MODELS.slice(0, 2)) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25000);
    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: 'POST',
          signal: controller.signal,
          headers: { 'Content-Type': 'application/json', 'X-goog-api-key': apiKey },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: system }] },
            contents,
            generationConfig: {
              maxOutputTokens: 1500,
              temperature: 0.6,
              ...(model.startsWith('gemini-3.5')
                ? { thinkingConfig: { thinkingLevel: 'minimal' } }
                : {}),
            },
          }),
        }
      );
      clearTimeout(timeout);
      if (!response.ok) throw new Error(`status ${response.status}`);
      const data = await response.json();
      const text = data.candidates?.[0]?.content?.parts
        ?.filter((p) => p.text)
        .map((p) => p.text)
        .join(' ')
        .trim();
      if (!text) throw new Error('empty response');
      logEvent('coach_chat', { model, chars: text.length });
      return text;
    } catch (e) {
      clearTimeout(timeout);
      lastErr = e;
    }
  }
  throw lastErr;
}

// ── "Make it harder" — mid-session intensity upgrades ────────────

const INTENSIFY_EXERCISE = {
  type: 'OBJECT',
  nullable: true,
  properties: {
    name: { type: 'STRING' },
    sets: { type: 'INTEGER' },
    reps: { type: 'STRING' },
    rpe: { type: 'STRING' },
    rest: { type: 'STRING' },
    notes: { type: 'STRING' },
    alt: { type: 'STRING' },
    suggestedWeight: { type: 'STRING' },
  },
  required: ['name', 'sets', 'reps'],
};

const INTENSIFY_SCHEMA = {
  type: 'OBJECT',
  properties: {
    note: { type: 'STRING' },
    options: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          kind: { type: 'STRING', enum: ['add', 'extraSet', 'replace'] },
          target: { type: 'STRING' },
          why: { type: 'STRING' },
          exercise: INTENSIFY_EXERCISE,
        },
        required: ['kind', 'why'],
      },
    },
  },
  required: ['options'],
};

/**
 * The athlete feels strong mid-session and wants more. Returns
 * { note, options: [{ kind: 'add'|'extraSet'|'replace', target, why, exercise }] }.
 * The note is a gentle recovery reminder (empty when recovery looks fine),
 * grounded in the same history + sleep/HRV data the plan was built from.
 */
export async function intensifyWorkout(today, history, healthLog = []) {
  const apiKey = getApiKey();
  if (!apiKey) throw new Error('No Gemini API key set — add it in Settings.');

  const p = today.plan || {};
  const checkin = today.checkin || {};
  const progress = (p.exercises || [])
    .map((ex, i) => {
      const done = (today.log?.[i] || [])
        .filter(setLogged)
        .map((s) => `${s.weight || '?'}x${s.reps || '?'}`)
        .join(', ');
      return `${i + 1}. ${ex.name} ${ex.sets}×${ex.reps}${ex.suggestedWeight ? ` @${ex.suggestedWeight}` : ''} — sets logged: ${done || 'none yet'}`;
    })
    .join('\n');

  const recovery = [];
  const t = healthTrend(healthLog, 5);
  if (t) recovery.push(`Watch data trend:\n${t}`);
  const todayNums = parseHealthNumbers(checkin.health);
  const base = healthBaseline(history, healthLog);
  if (todayNums.hrv && base.hrv) {
    const d = Math.round(((todayNums.hrv - base.hrv) / base.hrv) * 100);
    recovery.push(`HRV today ${todayNums.hrv} vs 30-day avg ${base.hrv} (${d >= 0 ? '+' : ''}${d}%)`);
  }
  if (todayNums.rhr && base.rhr) {
    const d = Math.round(((todayNums.rhr - base.rhr) / base.rhr) * 100);
    recovery.push(`RHR today ${todayNums.rhr} vs 30-day avg ${base.rhr} (${d >= 0 ? '+' : ''}${d}%)`);
  }
  const fatigue = fatigueSignal(history);
  if (fatigue) recovery.push(fatigue);

  const recent = history
    .slice(-3)
    .map((h) => `${h.date} ${h.plan?.sessionType} RPE ${h.fin?.rpe ?? '?'}`)
    .join('; ');

  const userMsg = `The athlete is mid-session TODAY and feels strong — they tapped "make it harder" and want to extend this workout.

TODAY (${today.date}) — ${p.sessionType}, plan with live progress:
${progress}
Time budget: ${checkin.timeAvail || '60'} min gym time. Check-in this morning: energy ${checkin.energy}/10, sleep ${checkin.sleep}, soreness ${checkin.soreness}${checkin.soreAreas ? ' (' + checkin.soreAreas + ')' : ''}.

RECOVERY DATA (today vs their own history):
${recovery.join('\n') || 'No watch data available — rely on check-in and training log.'}

PROGRESSION TARGETS (from logged history):
${progressionTargets(history) || 'No logged sets yet.'}
RECENT SESSIONS: ${recent || 'none logged'}

Offer 2-3 concrete ways to make today harder — AT MOST ONE of each kind:
- "add": ONE new exercise that fits the ${p.sessionType || 'current'} split and the remaining time ("exercise" required, sets 2-3).
- "extraSet": one extra set on the existing exercise that would benefit most ("target" = its exact name from the plan).
- "replace": swap an exercise with NO sets logged yet for a harder variation ("target" = exact name of the exercise being replaced, "exercise" = the harder one). Skip this kind if everything is already started.
Keep "why" under 10 words. Anchor any suggestedWeight on the logged history — no big jumps.
"note": ONLY IF the recovery data above (sleep, HRV vs baseline, RHR, fatigue trend) suggests today isn't ideal for extra load, write ONE gentle supportive sentence reminding them of that specific data point — a soft nudge, never a prohibition, no scolding. If recovery looks fine, use an empty string.`;

  let lastErr;
  for (const model of MODELS.slice(0, 2)) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25000);
    const startedAt = Date.now();
    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: 'POST',
          signal: controller.signal,
          headers: { 'Content-Type': 'application/json', 'X-goog-api-key': apiKey },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: coachRules() }] },
            contents: [{ role: 'user', parts: [{ text: userMsg }] }],
            generationConfig: {
              maxOutputTokens: 2000,
              temperature: 0.5,
              responseMimeType: 'application/json',
              responseSchema: INTENSIFY_SCHEMA,
              ...(model.startsWith('gemini-3.5')
                ? { thinkingConfig: { thinkingLevel: 'low' } }
                : {}),
            },
          }),
        }
      );
      clearTimeout(timeout);
      if (!response.ok) throw new Error(`status ${response.status}`);
      const data = await response.json();
      const text = data.candidates?.[0]?.content?.parts
        ?.filter((pt) => pt.text)
        .map((pt) => pt.text)
        .join('')
        .trim();
      if (!text) throw new Error('empty response');
      const parsed = JSON.parse(text);
      const names = new Set(
        (p.exercises || []).map((e) => e?.name?.trim().toLowerCase())
      );
      parsed.options = (parsed.options || [])
        .filter((o) =>
          o.kind === 'add'
            ? o.exercise?.name
            : o.kind === 'replace'
            ? o.exercise?.name && names.has(o.target?.trim().toLowerCase())
            : o.kind === 'extraSet' && names.has(o.target?.trim().toLowerCase())
        )
        .slice(0, 3);
      for (const o of parsed.options) {
        if (!o.exercise) continue;
        o.exercise.rpe ||= '7-8';
        o.exercise.rest ||= '90s';
        capSuggestedWeight(o.exercise, history);
      }
      logEvent('ai_intensify', {
        model,
        latencyMs: Date.now() - startedAt,
        options: parsed.options.map((o) => o.kind),
        hasNote: !!parsed.note,
      });
      return parsed;
    } catch (e) {
      clearTimeout(timeout);
      lastErr = e;
    }
  }
  throw lastErr;
}

/**
 * Two-sentence post-session debrief from the coach.
 */
export function generateDebrief(session, history) {
  const sets = (session.plan?.exercises || [])
    .map((ex, i) => {
      const done = (session.log?.[i] || [])
        .filter(setLogged)
        .map((s) => `${s.weight || '?'}x${s.reps || '?'}`)
        .join(', ');
      return `${ex.name} [${done || 'skipped'}]`;
    })
    .join('; ');
  const prev = history
    .slice(-3)
    .map((h) => `${h.date} ${h.plan?.sessionType} RPE ${h.fin?.rpe ?? '?'}`)
    .join('; ');

  return callGeminiText(
    `The athlete just finished today's session. Give a debrief: EXACTLY 2 short sentences — one on what went well, one on what you'll adjust next time. Plain text, no markdown, max 45 words total. Direct, no hype.

TODAY (${session.date}, ${session.plan?.sessionType}): ${sets}
Session RPE ${session.fin?.rpe}${session.fin?.pain ? ' | pain: ' + session.fin.pain : ''}${session.fin?.feedback ? ' | athlete says: ' + session.fin.feedback : ''}
RECENT: ${prev || 'first logged session'}`,
    120,
    'ai_debrief'
  );
}

/**
 * Short weekly review: what happened + a nudge for the coming week.
 */
export function generateWeeklyReview(summary) {
  return callGeminiText(
    `Write the athlete's weekly review: EXACTLY 2-3 short sentences — how the week went (sessions, progressions) and one concrete nudge for next week. Plain text, no markdown, max 55 words. Direct, no hype.

THIS WEEK: ${summary.count} sessions
${summary.lines}
LIFTS THAT MOVED UP: ${summary.progressions}`,
    140,
    'ai_weekly_review'
  );
}

/**
 * Generate a workout plan with automatic retry for rate limits.
 * @param {object} checkin - Check-in data
 * @param {Array} history - Session history
 * @param {function} onStatus - Optional callback for status messages
 */
export async function generateWorkoutPlan(checkin, history, onStatus) {
  const healthLog = await getAllHealth().catch(() => []);
  // Try each model in order — fallback on overload/503
  for (let mi = 0; mi < MODELS.length; mi++) {
    const model = MODELS[mi];
    try {
      if (onStatus && mi > 0) onStatus(`Trying ${model}…`);
      return await callGemini(checkin, history, model, healthLog);
    } catch (err) {
      // Model overloaded — try next model
      if (err.overloaded && mi < MODELS.length - 1) {
        console.warn(`[COACH] ${model} overloaded, trying next model`);
        if (onStatus) onStatus(`${model} is busy — switching model…`);
        await sleep(1000);
        continue;
      }

      // Rate limit — wait and retry same model
      if (err.message?.startsWith('RATE_LIMIT:')) {
        const waitSec = err.retryDelay || 45;
        if (onStatus) onStatus(`Rate limited — waiting ${waitSec}s…`);
        for (let s = waitSec; s > 0; s--) {
          if (onStatus) onStatus(`Rate limited — retrying in ${s}s…`);
          await sleep(1000);
        }
        // Retry same model once after waiting
        try {
          return await callGemini(checkin, history, model, healthLog);
        } catch (retryErr) {
          if (retryErr.overloaded && mi < MODELS.length - 1) continue;
          if (retryErr.message?.startsWith('RATE_LIMIT:')) {
            throw new Error('Rate limit hit twice. Wait a minute and try again.');
          }
          throw retryErr;
        }
      }

      // Other errors — try next model on first failure
      if (mi < MODELS.length - 1) {
        console.warn(`[COACH] ${model} failed, trying next`, err);
        continue;
      }

      throw err;
    }
  }
}
