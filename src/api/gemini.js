// ── Gemini API integration ───────────────────────────────────────
import { parsePlan } from '../utils/parser';
import { getApiKey } from '../utils/storage';
import { todayStr } from '../utils/helpers';

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
Rotate exercises sensibly, avoid repeating identical sessions, keep the split balanced based on the history provided. Do not invent history that isn't in the log.
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
                  .filter((s) => s.done)
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

TRAINING LOG (most recent last):
${histText}
${daysSince !== null ? `Days since last logged session: ${daysSince}${daysSince >= 7 ? ' — RETURNING FROM BREAK, apply reduced-volume rules.' : ''}` : ''}

BASE WORKOUT DATABASE:
${WORKOUT_DB}

Decide the right session for today and build it. ${JSON_SPEC}`;
}

/**
 * Call Google Gemini API to generate a workout plan.
 */
async function callGemini(checkin, history) {
  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error('No Gemini API key set. Go to Settings to add one.');
  }

  const userMsg = buildUserMessage(checkin, history);

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
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
          maxOutputTokens: 1000,
          temperature: 0.7,
        },
      }),
    }
  );

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

  return parsePlan(text);
}

/**
 * Generate a workout plan with one retry on failure.
 */
export async function generateWorkoutPlan(checkin, history) {
  try {
    return await callGemini(checkin, history);
  } catch (firstErr) {
    console.warn('First attempt failed, retrying once', firstErr);
    return await callGemini(checkin, history);
  }
}
