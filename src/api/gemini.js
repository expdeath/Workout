// ── Gemini API integration ───────────────────────────────────────
import { parsePlan } from '../utils/parser';
import { getApiKey } from '../utils/storage';
import { todayStr, setLogged } from '../utils/helpers';
import { buildLongTermSummary } from '../utils/aiContext';
import { logEvent } from '../db/db';

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
`;

// ── Coaching system prompt ───────────────────────────────────────
const COACH_RULES = `You are this person's long-term strength coach. Profile: IT desk job, long sitting periods. Goals: fat loss, muscle preservation/building, fitness, posture, avoid lower back pain, sustainable habits. Trains Push/Pull/Legs (flexible). Walks 12 min each way to the gym — count it in total time, treat as light warm-up/cool-down. Trains after 4PM day job, before a 1-2h evening job, so sessions must be efficient. Prefers 4-5 sessions/week Mon-Fri. Sessions 45-75 min.
Lower back: occasionally tight from sitting. Don't prohibit exercises; prefer supported/machine variations when appropriate, add technique cues. Adapt if sore today.
Progression: recommend small weight increases, extra reps, or holding, based on logged history. NEVER increase load if recovery looks poor. If returning from 1+ week break: reduce volume, avoid failure, reduce weights, expect DOMS.
Rotate exercises sensibly, avoid repeating identical sessions, keep the split balanced based on the history provided. Do not invent history that isn't in the log. Use the LONG-TERM TRAINING SUMMARY for progression decisions and split balance; the recent TRAINING LOG shows exact numbers for the last sessions.
Be direct and analytical. No hype. State uncertainty when the data is thin.`;

// ── JSON schema spec sent to the model ──────────────────────────
const JSON_SPEC = `Respond with ONLY minified valid JSON — no markdown fences, no preamble, no trailing text. BE EXTREMELY CONCISE in every string; total response must stay under 900 tokens. Schema:
{"sessionType":"Push|Pull|Legs|Active Recovery|Mobility|Rest Day|Light Cardio",
"title":"max 6 words",
"recoveryScore":0-100,
"reasoning":"max 2 short sentences",
"warmup":["max 3 items, max 8 words each"],
"exercises":[{"name":"","sets":3,"reps":"10-12","rpe":"7-8","rest":"90s","notes":"max 10 words or empty","alt":"max 5 words or empty","suggestedWeight":"e.g. 24kg or empty"}],
"cardio":{"desc":"max 8 words","duration":"e.g. 15min"} or null,
"cooldown":["max 3 items, max 6 words each"],
"estTimeMin":number including 24min walking,
"concerns":"max 12 words or empty"}
Max 6 exercises. If Rest Day, exercises=[]. For Active Recovery put the circuit in exercises.`;

/**
 * Build the user message from check-in data and history.
 */
function buildUserMessage(checkin, history) {
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
                  .map((s) => `${s.weight || '?'}x${s.reps || '?'}`)
                  .join(', ');
                return `${ex.name} [${sets || 'no sets logged'}]`;
              })
              .join('; ') +
            (h.finished
              ? ` | session RPE ${h.fin?.rpe ?? '?'}${h.fin?.pain ? ' | pain: ' + h.fin.pain : ''}${h.fin?.feedback ? ' | notes: ' + h.fin.feedback : ''}`
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
${checkin.notes ? '- Other notes: ' + checkin.notes : ''}

APPLE HEALTH DATA (pasted by user, may be empty):
${checkin.health || 'None provided today — rely on check-in + history.'}

LONG-TERM TRAINING SUMMARY (compressed from full history):
${buildLongTermSummary(history) || 'Not enough history yet — rely on the recent log below.'}

TRAINING LOG (last sessions in detail, most recent last):
${histText}
${daysSince !== null ? `Days since last logged session: ${daysSince}${daysSince >= 7 ? ' — RETURNING FROM BREAK, apply reduced-volume rules.' : ''}` : ''}

BASE WORKOUT DATABASE:
${WORKOUT_DB}

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
async function callGemini(checkin, history, model = MODELS[0]) {
  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error('No Gemini API key set. Go to Settings to add one.');
  }

  const userMsg = buildUserMessage(checkin, history);

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
            parts: [{ text: COACH_RULES }],
          },
          contents: [
            {
              role: 'user',
              parts: [{ text: userMsg }],
            },
          ],
          generationConfig: {
            maxOutputTokens: 4000,
            temperature: 0.7,
            // 3.5 Flash thinks at "medium" by default and can spend the
            // whole budget reasoning before emitting the JSON — we want
            // fast structured output, not deliberation
            ...(model.startsWith('gemini-3.5')
              ? { thinkingConfig: { thinkingLevel: 'minimal' } }
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

  return parsePlan(text);
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
            system_instruction: { parts: [{ text: COACH_RULES }] },
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
  // Try each model in order — fallback on overload/503
  for (let mi = 0; mi < MODELS.length; mi++) {
    const model = MODELS[mi];
    try {
      if (onStatus && mi > 0) onStatus(`Trying ${model}…`);
      return await callGemini(checkin, history, model);
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
          return await callGemini(checkin, history, model);
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
