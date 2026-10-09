package com.expdeath.coach.ai

import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.SavedWorkout
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.models.parseInt
import com.expdeath.coach.persistence.AIConsent
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.Http
import kotlinx.coroutines.delay
import kotlin.coroutines.cancellation.CancellationException
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Base64
import java.util.Locale
import kotlin.math.ceil

/** Builds a JSON tree from Kotlin values (request bodies and schemas). */
internal fun j(x: Any?): JSONValue = when (x) {
    null -> JSONValue.Null
    is JSONValue -> x
    is String -> JSONValue.Str(x)
    is Boolean -> JSONValue.Bool(x)
    is Number -> JSONValue.Num(x.toDouble())
    is List<*> -> JSONValue.Arr(x.map { j(it) })
    is Map<*, *> -> JSONValue.Obj(LinkedHashMap<String, JSONValue>().also { m -> x.forEach { (k, v) -> m[k.toString()] = j(v) } })
    else -> JSONValue.Str(x.toString())
}

internal fun o(vararg pairs: Pair<String, Any?>): JSONValue = j(linkedMapOf(*pairs))

/** Direct Gemini API integration — ports src/api/gemini.js (and
 *  GeminiClient.swift) function-for-function. No backend: the app calls
 *  generativelanguage.googleapis.com straight from the device, with the
 *  same model fallback ladder and the same deterministic guardrails on the
 *  model's suggested weights. COACH Pro requests go through the COACH server. */
object Gemini {

    // ── Errors ───────────────────────────────────────────────────────

    sealed class GeminiError(message: String) : Exception(message) {
        class NoApiKey : GeminiError("No Gemini API key set. Go to Settings to add one.")
        class NoConsent : GeminiError("The AI coach is off — turn it on in Settings → AI Coach. Your data only goes to Google Gemini with your OK.")
        class Server(m: String) : GeminiError(m)
        class RateLimited(val retryDelay: Int) : GeminiError("Rate limit hit twice. Wait a minute and try again.")
        class Overloaded(model: String) : GeminiError("$model is overloaded.")
        class Blocked(reason: String) : GeminiError("Request blocked by Gemini: $reason")
        class Http(status: Int, m: String) : GeminiError("Gemini API error ($status): $m")
        class Message(m: String) : GeminiError(m)
    }

    // Models to try in order — if one is overloaded, try the next.
    // 2.5 Flash was dropped — Google now 404s it for new API keys.
    private val models = listOf("gemini-3.5-flash", "gemini-3.1-flash-lite", "gemini-3.6-flash")

    // 3.5+ Flash models take thinkingLevel; the default burns tokens and truncates.
    private fun supportsThinkingLevel(model: String) = Regex("""^gemini-3\.[5-9]-flash$""").matches(model)

    // ── Workout database (menu, not a script) ────────────────────────

    private val workoutDB = """
Exercise menu — staples exist ONLY to anchor long-term progression tracking on a couple of numbers per split, not to be run unchanged every time. Per session, keep AT MOST 1-2 staples (whichever the athlete is actively progressing) and fill the remaining slots from that day's pool — favor picks not seen in the last 2-3 sessions of the same split. Respect equipment limits. 1-2 core finishers may be appended to any lifting day.

PUSH DAY — Warm-up: 15min Stairmaster OR light warm-up sets of the first press.
Staples:
- Flat Dumbbell Press 3x10-12 (alt: Seated Chest Press Machine, Barbell Bench Press)
- Incline Dumbbell Press 3x10-12 (alt: Incline Machine Press, Low-to-High Cable Fly)
- Machine Shoulder Press 3x10-12 (alt: Seated Dumbbell Shoulder Press)
- Cable Lateral Raise 3x12-15 (alt: Dumbbell Lateral Raise)
- Rope Tricep Pushdown 3x12-15 (alt: Straight-Bar Pushdown)
Pool: Pec Deck Fly 3x12-15 · Cable Crossover 3x12-15 · Machine Dips 3x8-10 (alt: Bench Dips) · Overhead Rope Tricep Extension 3x10-12 · Skull Crushers 3x10-12 · Close-Grip Bench Press 3x8-10 · Arnold Press 3x10-12 · Push-Ups 3xAMRAP (finisher)
Cooldown: doorway chest stretch, overhead tricep stretch.

PULL DAY — Warm-up: 15min stationary bike OR light first-row sets.
Staples:
- Chest Supported Row 3x8-10 (alt: Seated Cable Row)
- Lat Pulldown 3x8-10 (alt: Assisted Pull-Up, Neutral-Grip Pulldown)
- Machine Rear Delt Fly 3x12-15 (alt: Face Pull)
- Cable Curl 3x10-12 (alt: Dumbbell Curl)
Pool: One-Arm Dumbbell Row 3x8-10/side · Straight-Arm Pulldown 3x12-15 · Barbell Row 3x8-10 · Hammer Curl 3x10-12 · Incline Dumbbell Curl 3x10-12 · Preacher Curl 3x10-12 · Dumbbell Shrug 3x12-15 · Back Extension 3x12 · Romanian Deadlift 3x8-10 (also fits Legs)
Cooldown: lat stretch, bicep stretch.

LEG DAY — Warm-up: 15min stationary bike + bodyweight squats x10.
Staples:
- Leg Press 3x10-12 (alt: Hack Squat, Goblet Squat)
- Seated Leg Curl 3x10-12 (alt: Lying Leg Curl, Romanian Deadlift)
- Leg Extension 3x12-15
- Calf Press 3x15 (alt: Standing Calf Raise)
Pool: Bulgarian Split Squat 3x8-10/side · Walking Lunges 3x10/side · Dumbbell Step-Ups 3x10/side · Hip Thrust 3x10-12 · Adductor Machine 3x12-15 · Abductor Machine 3x12-15 · Single-Leg Press 3x10/side · Smith Machine Squat 3x8-10
Cooldown: quad stretch, hamstring stretch.

CORE FINISHERS (append 1-2 to any day): Plank 3x45s · Side Plank 2x30s/side · Cable Crunch 3x12-15 · Hanging Knee Raise 3x10-12 · Pallof Press 3x10/side · Dead Bug 3x10/side · Russian Twist 3x20 · Ab Wheel Rollout 3x8-10

CORE DAY (standalone session) — Warm-up: 5min easy bike + cat-cow x10.
Staples:
- Hanging Leg Raise 3x10-12 (alt: Hanging Knee Raise, Captain's Chair Knee Raise)
- Cable Crunch 3x12-15 (alt: Weighted Sit-Up)
- Pallof Press 3x10/side (alt: Standing Cable Woodchop)
Pool: Weighted Plank 3x45-60s · Side Plank 2x30-45s/side · Ab Wheel Rollout 3x8-10 · Dead Bug 3x10/side · Russian Twist 3x20 · Hollow Hold 3x20-30s · Back Extension 3x12 (anti-extension balance) · Farmer's Carry 3x40m (anti-lateral flexion)
Cooldown: cobra stretch, seated spinal twist.

ACTIVE RECOVERY — Option 1: 30min stationary bike or incline walk, zone 2.
Option 2: 3 rounds — dead bugs x10/side, bird dog x10/side, plank 45s, side plank 30s/side, hollow hold 20-30s.
Option 3: 20min easy swim or rowing machine + 10min stretching.

CARDIO DAY — Option 1: 35-45min zone 2 — stationary bike, incline treadmill walk, stairmaster, rowing machine, or easy run.
Option 2: intervals — 10min easy bike, then 8 × (1min hard / 2min easy), 5min cooldown walk.
Option 3: 25-30min run or 5k treadmill at steady pace.
Option 4: 3 rounds — 500m row, 1min jump rope, 10 kettlebell swings, 1min rest.
Finish: 5min full-body stretch.

STRETCH & MOBILITY DAY — 10min easy bike, then 2 rounds: cat-cow x10, world's greatest stretch x5/side, 90/90 hip switches x10/side, couch stretch 45s/side, hamstring floss x10/side, thoracic wall opener 45s/side, doorway chest stretch 45s/side, deep squat hold 30s. Optional extras: pigeon pose 45s/side, child's pose 60s, band shoulder dislocates x10, calf stretch 45s/side.

FULL BODY MIX (fun day) — pick 5-6, 2 sets each, moderate load, superset pairs, 60s rests: leg press, goblet squat, chest press machine, chest supported row, lat pulldown, hip thrust, cable lateral raise, cable curl, rope pushdown, kettlebell swing, plank 45s.""".trimStart('\n')

    private const val defaultProfile = "Recreational lifter, trains Push/Pull/Legs at a commercial gym. Goals: strength, muscle, sustainable habits. Sessions 45-75 min, 4-5 per week."

    private fun coachRules(): String {
        val profile = LocalStore.backup.aiSettings.profile.trim()
        val p = profile.ifEmpty { defaultProfile }
        return """You are this person's long-term strength coach. PROFILE: $p
Don't prohibit exercises; prefer supported/machine variations when appropriate, add technique cues. Adapt to today's check-in (soreness, tightness, energy).
Progression: recommend small weight increases, extra reps, or holding, based on logged history. NEVER increase load if recovery looks poor. If returning from 1+ week break: reduce volume, avoid failure, reduce weights, expect DOMS.
Logged sets may carry the athlete's own effort tag — (easy) = clear room to progress, (good) = about right, (grind) = near-failure. Never add load to a lift whose last sets were grinds; treat all-easy sets as a green light for a bigger jump.
Rotate exercises HARD — before picking, find the most recent session of the SAME split in the TRAINING LOG and compare exercise-by-exercise: if 3+ names match, that's a repeat, not a plan. The workout database separates STAPLES (keep AT MOST 1-2 per session — only the ones you're actively tracking numeric progress on) from a rotation POOL: fill every other slot from the pool, preferring picks not used in that split's last 2-3 sessions. Never send out the exact same exercise list two sessions running for the same split. Do not invent history that isn't in the log. Occasionally append a core finisher to a lifting day when time allows.
VARIETY: training is NOT a rigid Push/Pull/Legs loop. Read the history — after 3+ consecutive lifting days, or when no cardio or mobility day appears in the last 7-10 days, schedule a Cardio or Stretch & Mobility day (recovery quality decides which). If the MUSCLE BALANCE note flags Core as untrained 10+ days, schedule a standalone Core day from the CORE DAY block instead of just appending a finisher — it needs to compete for a rotation slot like Cardio/Stretch do, not stay an afterthought. A Full Body mix day is a good occasional change of pace. If the check-in states a session preference, honor it — it overrides the rotation. Use the LONG-TERM TRAINING SUMMARY for progression decisions and split balance; the recent TRAINING LOG shows exact numbers for the last sessions.
Be direct and analytical. No hype. State uncertainty when the data is thin."""
    }

    private fun planSystem(): String {
        val routine = LocalStore.backup.aiSettings.routine.trim()
        return "${coachRules()}\n\nBASE WORKOUT DATABASE:\n${routine.ifEmpty { workoutDB }}"
    }

    private const val jsonSpec = """BE EXTREMELY CONCISE in every string; total response must stay under 900 tokens. Field rules:
{"sessionType":"Push|Pull|Legs|Full Body|Core|Cardio|Stretch & Mobility|Active Recovery|Rest Day",
"title":"max 6 words",
"recoveryScore":0-100,
"reasoning":"max 2 short sentences",
"warmup":["max 3 items, max 8 words each"],
"exercises":[{"name":"","sets":3,"reps":"10-12","rpe":"7-8","rest":"90s","notes":"max 10 words or empty","alt":"max 5 words or empty","suggestedWeight":"e.g. 24kg or empty","superset":"A/B or empty"}],
"cardio":{"desc":"max 8 words","duration":"e.g. 15min"} or null,
"cooldown":["max 3 items, max 6 words each"],
"estTimeMin":number including 24min walking,
"concerns":"max 12 words or empty"}
Max 6 exercises. If Rest Day, exercises=[]. For Cardio, Stretch & Mobility, Active Recovery, or Core put the circuit/intervals/stretches/core-moves in exercises (sets=rounds, reps=duration or count, weight empty).
Supersets: when time is tight or two accessories pair well (non-competing muscles), give BOTH exercises the same "superset" letter and place them adjacently — the athlete alternates sets and shares the rest. Never superset heavy compounds."""

    private val STR = mapOf("type" to "STRING")
    private val INT = mapOf("type" to "INTEGER")
    private val STRS = mapOf("type" to "ARRAY", "items" to STR)

    private val planSchema = o(
        "type" to "OBJECT",
        "properties" to linkedMapOf(
            "sessionType" to mapOf("type" to "STRING", "enum" to listOf("Push", "Pull", "Legs", "Full Body", "Core", "Cardio", "Stretch & Mobility", "Active Recovery", "Rest Day")),
            "title" to STR, "recoveryScore" to INT, "reasoning" to STR, "warmup" to STRS,
            "exercises" to mapOf(
                "type" to "ARRAY",
                "items" to linkedMapOf(
                    "type" to "OBJECT",
                    "properties" to linkedMapOf(
                        "name" to STR, "sets" to INT, "reps" to STR, "rpe" to STR, "rest" to STR,
                        "notes" to STR, "alt" to STR, "suggestedWeight" to STR, "superset" to STR,
                    ),
                    "required" to listOf("name", "sets", "reps"),
                ),
            ),
            "cardio" to linkedMapOf("type" to "OBJECT", "nullable" to true, "properties" to linkedMapOf("desc" to STR, "duration" to STR)),
            "cooldown" to STRS, "estTimeMin" to INT, "concerns" to STR,
        ),
        "required" to listOf("sessionType", "exercises", "estTimeMin"),
    )

    // ── Deterministic guardrails on suggested weights ────────────────

    private const val maxJumpFactor = 1.15 // suggested load ≤ 15% over last logged
    private const val minJumpKg = 2.5
    private const val plateStepKg = 2.5
    private const val maxWeightKg = 200.0

    private fun capSuggestedWeight(ex: Plan.Exercise, history: List<Session>): Plan.Exercise? {
        val w = Stats.firstMatch("""([\d.]+)""", ex.suggestedWeight)?.getOrNull(1)?.let { parseDouble(it) } ?: return null
        val lp = Stats.lastPerformance(history, ex.name)
        val lastW = lp?.sets?.mapNotNull { parseDouble(it.weight) }?.maxOrNull() ?: 0.0
        val cap = if (lastW > 0) minOf(maxOf(lastW * maxJumpFactor, lastW + minJumpKg), maxWeightKg) else maxWeightKg
        if (w <= cap) return null
        val rounded = (cap / plateStepKg).rounded() * plateStepKg
        return ex.copy(suggestedWeight = "${fmtKg(rounded)}kg")
    }

    private fun fmtKg(v: Double) = if (v % 1.0 == 0.0) v.toInt().toString() else v.toString()

    fun sanitizePlan(plan: Plan, history: List<Session>, checkin: Checkin): Plan {
        var p = plan
        var changed = false
        if (p.exercises.size > 6) {
            p = p.copy(exercises = p.exercises.take(6))
            changed = true
        }
        p = p.copy(exercises = p.exercises.map { ex -> capSuggestedWeight(ex, history)?.also { changed = true } ?: ex })
        val avail = parseInt(checkin.timeAvail) ?: 60
        if (p.estTimeMin > avail + 24 + 10) {
            p = p.copy(estTimeMin = avail + 24)
            changed = true
        }
        if (changed) LocalStore.logEvent("plan_sanitized", mapOf("sessionType" to JSONValue.Str(p.sessionType)))
        return p
    }

    // ── User message ─────────────────────────────────────────────────

    private val wish = mapOf(
        "lift" to "The athlete wants to LIFT today — pick the right strength session for the split balance.",
        "cardio" to "The athlete asked for a CARDIO day — build it around conditioning (bike/stairs/incline walk/intervals), no lifting session.",
        "stretch" to "The athlete asked for a STRETCH & MOBILITY day — a full mobility/flexibility session, no heavy lifting.",
        "core" to "The athlete asked for a CORE day — build a standalone core session from the CORE DAY block, no other lifting.",
        "surprise" to "The athlete asked you to SURPRISE them — build something genuinely different from the recent sessions (mixed circuit, superset full-body, conditioning + core, new variations). Keep it safe and equipment-realistic, but make it fun.",
    )

    private fun pct(t: Double, b: Double) = (((t - b) / b) * 100).rounded().toInt()
    private fun signed(d: Int) = "${if (d >= 0) "+" else ""}$d"

    private fun baselineComparison(checkin: Checkin, history: List<Session>, healthLog: List<HealthRow>): String {
        val health = checkin.health
        if (health.isNullOrEmpty()) return ""
        val today = Stats.parseHealthNumbers(health)
        val base = Stats.healthBaseline(history, healthLog)
        val lines = ArrayList<String>()
        if (today.hrv != null && base.hrv != null) {
            val d = pct(today.hrv, base.hrv)
            lines.add("HRV ${fmtKg(today.hrv)} vs 30-day avg ${fmtKg(base.hrv)} (${signed(d)}%)${if (d <= -10) " — recovery below normal" else ""}")
        }
        if (today.rhr != null && base.rhr != null) {
            val d = pct(today.rhr, base.rhr)
            lines.add("RHR ${fmtKg(today.rhr)} vs 30-day avg ${fmtKg(base.rhr)} (${signed(d)}%)${if (d >= 7) " — elevated, possible fatigue/illness" else ""}")
        }
        if (today.sleepH != null && base.sleepH != null) {
            val d = pct(today.sleepH, base.sleepH)
            lines.add("Sleep ${fmtKg(today.sleepH)}h vs 30-day avg ${fmtKg(base.sleepH)}h${if (d <= -20) " — clearly short, reduce intensity" else ""}")
        }
        if (today.respRate != null && base.respRate != null) {
            val d = pct(today.respRate, base.respRate)
            lines.add("Respiratory rate ${fmtKg(today.respRate)} vs avg ${fmtKg(base.respRate)}${if (d >= 10) " — elevated, possible illness" else ""}")
        }
        if (today.wristC != null && base.wristC != null) {
            val d = ((today.wristC - base.wristC) * 10).rounded() / 10
            lines.add("Wrist temp ${fmtKg(today.wristC)}°C vs avg ${fmtKg(base.wristC)}°C${if (d >= 0.4) " (+${fmtKg(d)}°C — possible illness/strain, be conservative)" else ""}")
        }
        return if (lines.isEmpty()) "" else "Baseline comparison (computed): " + lines.joinToString("; ")
    }

    private fun setsText(sets: List<com.expdeath.coach.models.SetLog>) =
        sets.joinToString(", ") { s -> s.formatted + (if (s.effort.isEmpty()) "" else "(${s.effort})") }

    private fun sessionLogLine(h: Session): String {
        val exercises = h.plan.exercises.mapIndexed { i, ex ->
            val sets = setsText((h.log.getOrNull(i) ?: emptyList()).filter { it.isLogged })
            "${ex.name} [${sets.ifEmpty { "no sets logged" }}]"
        }.joinToString("; ")
        val outcome = if (h.finished) {
            var s = " | session RPE ${h.fin?.rpe?.toString() ?: "?"}"
            h.durationMin?.let { s += " | took ${it}min" }
            h.fin?.pain?.takeIf { it.isNotEmpty() }?.let { s += " | pain: $it" }
            h.fin?.feedback?.takeIf { it.isNotEmpty() }?.let { s += " | notes: $it" }
            s
        } else " | NOT COMPLETED"
        return "${h.date} — ${h.plan.sessionType}: $exercises$outcome"
    }

    fun buildUserMessage(checkin: Checkin, history: List<Session>, healthLog: List<HealthRow> = emptyList(), template: SavedWorkout? = null): String {
        val settings = LocalStore.backup.aiSettings
        val recent = history.takeLast(6)
        val histText = if (recent.isEmpty())
            "No logged sessions yet in this app. Treat as a fresh start — use the base workout database, moderate volume, and ask nothing (choose sensibly)."
        else recent.joinToString("\n") { sessionLogLine(it) }
        val daysSince: Int? = if (recent.isEmpty()) null
        else ((Stats.dateMs(Helpers.todayStr()) - Stats.dateMs(recent.last().date)) / 86400).rounded().toInt()
        val lastDebrief = recent.lastOrNull()?.debrief ?: ""

        val normalized = checkin.health?.let { Stats.fmtHealthLine(Stats.parseHealthNumbers(it)) } ?: ""
        val trend = Stats.healthTrend(healthLog)
        val baselines = baselineComparison(checkin, history, healthLog)
        val deload = Stats.deloadSignal(history)
        val muscleGap = Stats.muscleGapNote(history)
        val goals = settings.goals.trim()
        val equipment = settings.equipment.trim()
        val cueLines = settings.cueNotes.entries.take(15).joinToString("\n") { "- ${it.key}: ${it.value}" }
        val weekday = LocalDate.now(Helpers.zone).dayOfWeek.getDisplayName(TextStyle.FULL, Locale.getDefault())

        val out = StringBuilder()
        out.append("\nTODAY: ${Helpers.todayStr()} ($weekday)\n\n")
        out.append("CHECK-IN:\n")
        out.append("- Energy: ${checkin.energy}/10\n")
        out.append("- Sleep last night: ${checkin.sleep}\n")
        out.append("- Soreness: ${checkin.soreness}${if (checkin.soreAreas.isEmpty()) "" else " (${checkin.soreAreas})"}\n")
        out.append("- Lower back tight today: ${if (checkin.backTight) "YES — adapt exercise selection" else "no"}\n")
        out.append("- Time available today (gym time, walking excluded): ${checkin.timeAvail} min\n")
        wish[checkin.wish]?.let { out.append("- SESSION PREFERENCE (honor this): $it\n") }
        if (checkin.prioritizeMuscle.isNotEmpty()) {
            out.append("- Athlete asked to prioritize ${checkin.prioritizeMuscle} today (untrained 10+ days) — bias exercise selection and/or session type toward this group if recovery allows.\n")
        }
        val bw = parseDouble(checkin.bodyKg)
        if (bw != null && bw > 0) out.append("- Body weight today: ${checkin.bodyKg}kg\n")
        if (checkin.notes.isNotEmpty()) out.append("- Other notes: ${checkin.notes}\n")

        out.append("\nAPPLE HEALTH DATA (raw Watch payload, may be empty):\n")
        out.append((if (checkin.health?.isNotEmpty() == true) checkin.health else "None provided today — rely on check-in + history.") + "\n")
        if (normalized.isNotEmpty()) out.append("Normalized by app (sleep deduped to hours — trust these units): $normalized\n")
        if (trend.isNotEmpty()) out.append("WATCH DATA TREND (daily, most recent last):\n$trend\n")
        if (baselines.isNotEmpty()) out.append("$baselines\n")
        if (deload != null) out.append("\nDELOAD WATCH (computed): ${deload.reason} Honor this unless today's readiness is clearly excellent.\n")
        if (muscleGap.isNotEmpty()) out.append("\n$muscleGap\n")
        if (goals.isNotEmpty()) out.append("\nATHLETE'S STATED GOALS (steer selection and progression toward these):\n$goals\n")
        if (equipment.isNotEmpty()) out.append("\nGYM EQUIPMENT & LIMITS (HARD CONSTRAINT — never prescribe anything unavailable; respect load limits):\n$equipment\n")
        if (cueLines.isNotEmpty()) out.append("\nATHLETE'S OWN EXERCISE NOTES (persistent cue cards — respect them when picking/prescribing):\n$cueLines\n")

        out.append("\nPROGRESSION TARGETS (computed deterministically from the logs — anchor suggestedWeight on these):\n")
        out.append(Stats.progressionTargets(history).ifEmpty { "No logged sets yet." } + "\n")

        out.append("\nLONG-TERM TRAINING SUMMARY (compressed from full history):\n")
        out.append(AIContext.buildLongTermSummary(history).ifEmpty { "Not enough history yet — rely on the recent log below." } + "\n")

        out.append("\nTRAINING LOG (last sessions in detail, most recent last):\n$histText\n")
        if (daysSince != null) {
            out.append("Days since last logged session: $daysSince${if (daysSince >= 7) " — RETURNING FROM BREAK, apply reduced-volume rules." else ""}\n")
        }
        if (lastDebrief.isNotEmpty()) out.append("\nYOUR OWN COACHING NOTE AFTER THE LAST SESSION (follow through on it): $lastDebrief\n")

        out.append("\n${template?.let { templateInstruction(it) } ?: "Decide the right session for today and build it."} $jsonSpec")
        return out.toString()
    }

    /** The athlete picked one of their saved workouts (templateInstruction in
     *  gemini.js). Keep-exact: the coach only fills weights and cues, and
     *  Workouts.enforceExact holds it to that. */
    fun templateInstruction(w: SavedWorkout): String {
        val brief = Workouts.brief(w)
        if (!w.adapt) {
            return "TODAY THE ATHLETE IS DOING THEIR SAVED WORKOUT — $brief\n\n" +
                "Use EXACTLY these exercises, in this order, with these sets and reps — do not add, remove, reorder or swap anything (a trainer wrote it; respect it). Where a weight is given, keep it. Where none is given, fill suggestedWeight from PROGRESSION TARGETS / the training log. Add short form cues in notes only when useful. Set sessionType to the closest match and title to the workout's name. If today's recovery data or check-in is worrying, say so in \"concerns\" — but still keep the workout as written."
        }
        return "TODAY THE ATHLETE WANTS TO DO THEIR SAVED WORKOUT, ADAPTED TO TODAY — $brief\n\n" +
            "Use it as the base and keep its intent and exercise choices. Adapt only where today's check-in, recovery data, soreness, pain or time make it sensible: fewer sets or lighter loads on a poor day, a safer swap for something that would aggravate soreness, trimming to fit the time. Fill suggestedWeight from the training log where none is given. In \"reasoning\", say plainly what you changed from the saved workout and why (or that you kept it as written)."
    }

    // ── Networking core ──────────────────────────────────────────────

    private fun endpoint(model: String) = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent"

    /** Low-level call: posts one generateContent request and extracts the
     *  text from the first candidate. Callers interpret rate-limit/overload
     *  errors themselves (retry ladder vs simple model fallback). */
    private suspend fun post(model: String, systemInstruction: String, contents: List<JSONValue>, generationConfig: JSONValue, timeoutSec: Long): String {
        // every Gemini request passes here: nothing leaves without consent
        if (!AIConsent.allowed) throw GeminiError.NoConsent()
        val body = o(
            "system_instruction" to o("parts" to listOf(o("text" to systemInstruction))),
            "contents" to contents,
            "generationConfig" to generationConfig,
        )
        val pro = Cloud.proActive
        val r = if (pro) {
            // COACH Pro: the COACH server adds the owner's key (functions/index.js)
            Http.request(
                "${Cloud.functionsBase}/coach", "POST",
                mapOf("Authorization" to "Bearer ${Cloud.idToken()}"),
                o("model" to model, "body" to body).toJsonString().toByteArray(), timeoutSec = timeoutSec,
            )
        } else {
            if (Cloud.geminiKey.isEmpty()) throw GeminiError.NoApiKey()
            Http.request(endpoint(model), "POST", mapOf("X-goog-api-key" to Cloud.geminiKey), body.toJsonString().toByteArray(), timeoutSec = timeoutSec)
        }
        val obj = JSONValue.parse(r.text)?.obj
        val errMsg = obj?.get("error")?.obj?.get("message")?.string

        // the COACH server's own refusals (not Pro, consent off, today's
        // limit) — final: another model won't change the answer
        if (pro && r.status in listOf(401, 402, 403)) throw GeminiError.Server(errMsg ?: "COACH Pro couldn't answer — try again.")

        if (r.status == 429) {
            var retryDelay = 45
            if (errMsg != null) {
                if (errMsg.contains("limit: 0")) {
                    throw GeminiError.Message("Your API key has no quota (limit: 0). This usually means your key is an old standard key that Google has blocked since June 2026. Go to aistudio.google.com → API Keys → Create a NEW API key (it will be an auth key automatically). Then paste it in Settings.")
                }
                Stats.firstMatch("""retry in ([\d.]+)s""", errMsg)?.getOrNull(1)?.let { parseDouble(it) }?.let { retryDelay = ceil(it).toInt() }
            }
            throw GeminiError.RateLimited(minOf(retryDelay, 90))
        }
        if (r.status == 503) throw GeminiError.Overloaded(model)
        if (r.status != 200) throw GeminiError.Http(r.status, errMsg ?: r.text)

        obj?.get("promptFeedback")?.obj?.get("blockReason")?.string?.let { throw GeminiError.Blocked(it) }
        val candidate = obj?.get("candidates")?.array?.firstOrNull()?.obj
            ?: throw GeminiError.Message("No candidates in Gemini response — the request may have been filtered.")
        val finish = candidate["finishReason"]?.string
        if (finish == "SAFETY") throw GeminiError.Message("Response blocked by Gemini safety filters. Try again.")
        val text = (candidate["content"]?.obj?.get("parts")?.array ?: emptyList()).mapNotNull { it.obj?.get("text")?.string }.joinToString("\n")
        if (text.isEmpty()) throw GeminiError.Message("Empty response from Gemini. Finish reason: ${finish ?: "unknown"}")
        return text
    }

    /** Strips ```json fences, extracts the {...} span, and repairs a
     *  truncated tail by closing open brackets/strings — parsePlan() in
     *  src/utils/parser.js. */
    fun repairAndDecodePlan(raw: String): Plan {
        var s = raw.replace("```json", "").replace("```", "").trim()
        val start = s.indexOf('{')
        if (start < 0) throw GeminiError.Message("no JSON in response")
        s = s.substring(start)

        val end = s.lastIndexOf('}')
        if (end >= 0) {
            try { return Plan.fromAI(s.substring(0, end + 1)) } catch (_: Exception) {}
        }

        // Repair pass: walk the string, track open structures, close them.
        val out = StringBuilder()
        val stack = ArrayList<Char>()
        var inStr = false
        var esc = false
        for (ch in s) {
            out.append(ch)
            if (inStr) {
                if (esc) esc = false
                else if (ch == '\\') esc = true
                else if (ch == '"') inStr = false
                continue
            }
            when (ch) {
                '"' -> inStr = true
                '{' -> stack.add('}')
                '[' -> stack.add(']')
                '}', ']' -> if (stack.isNotEmpty()) stack.removeAt(stack.size - 1)
            }
        }
        if (inStr) out.append('"')
        var str = out.toString()
        while (str.endsWith(",") || str.endsWith(", ")) str = str.dropLast(1)
        val sb = StringBuilder(str)
        while (stack.isNotEmpty()) sb.append(stack.removeAt(stack.size - 1))
        return Plan.fromAI(sb.toString())
    }

    private fun userContent(text: String) = listOf(o("role" to "user", "parts" to listOf(o("text" to text))))

    private suspend fun callGemini(checkin: Checkin, history: List<Session>, model: String, healthLog: List<HealthRow>, template: SavedWorkout?): Plan {
        val userMsg = buildUserMessage(checkin, history, healthLog, template)
        LocalStore.logEvent("ai_request", mapOf("model" to JSONValue.Str(model)))
        val started = System.currentTimeMillis()
        val config = linkedMapOf<String, Any?>(
            "maxOutputTokens" to 4000,
            "temperature" to if (checkin.wish == "surprise") 0.9 else 0.65,
            "responseMimeType" to "application/json",
            "responseSchema" to planSchema,
        )
        if (supportsThinkingLevel(model)) config["thinkingConfig"] = mapOf("thinkingLevel" to "low")
        try {
            val text = post(model, planSystem(), userContent(userMsg), j(config), 60)
            LocalStore.logEvent("ai_response", mapOf("model" to JSONValue.Str(model), "chars" to JSONValue.Num(text.length.toDouble()), "raw" to JSONValue.Str(text)))
            val plan = repairAndDecodePlan(text)
            return sanitizePlan(plan, history, checkin)
        } catch (e: Exception) {
            LocalStore.logEvent("ai_error", mapOf(
                "model" to JSONValue.Str(model), "message" to JSONValue.Str(e.message ?: e.toString()),
                "latencyMs" to JSONValue.Num((System.currentTimeMillis() - started).toDouble()),
            ))
            throw e
        }
    }

    private suspend fun callGeminiText(userMsg: String, maxTokens: Int, eventType: String): String {
        if (!Cloud.aiReady) throw GeminiError.NoApiKey()
        var lastErr: Exception = GeminiError.Message("no models tried")
        for (model in models.take(2)) {
            val config = linkedMapOf<String, Any?>("maxOutputTokens" to maxTokens + 1000, "temperature" to 0.6)
            if (supportsThinkingLevel(model)) config["thinkingConfig"] = mapOf("thinkingLevel" to "minimal")
            try {
                val text = post(model, coachRules(), userContent(userMsg), j(config), 20)
                LocalStore.logEvent(eventType, mapOf("model" to JSONValue.Str(model), "raw" to JSONValue.Str(text)))
                return text
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                lastErr = e
            }
        }
        throw lastErr
    }

    // ── Coach chat ───────────────────────────────────────────────────

    data class ChatMessage(val role: String, val text: String) // role: "user" | "coach"

    private fun sessionDetail(s: Session): String {
        val lines = s.plan.exercises.mapIndexed { i, ex ->
            val sets = (s.log.getOrNull(i) ?: emptyList()).filter { it.isLogged }.joinToString(" ") { it.formatted }
            "${ex.name}: ${sets.ifEmpty { "—" }}"
        }
        val parts = ArrayList<String>()
        parts.add("${s.date} ${s.plan.sessionType}${s.durationMin?.let { " · ${it}min" } ?: ""}")
        parts.addAll(lines)
        s.fin?.let { fin ->
            var line = "RPE ${fin.rpe}/10"
            if (fin.pain.isNotEmpty()) line += " · pain: ${fin.pain}"
            if (fin.feedback.isNotEmpty()) line += " · feedback: ${fin.feedback}"
            parts.add(line)
        }
        if (!s.debrief.isNullOrEmpty()) parts.add("Debrief already given: ${s.debrief}")
        return parts.filter { it.isNotEmpty() }.joinToString("\n")
    }

    suspend fun askCoach(messages: List<ChatMessage>, history: List<Session> = emptyList(), todayPlan: Session? = null, healthLog: List<HealthRow> = emptyList(), focusSession: Session? = null): String {
        if (!Cloud.aiReady) throw GeminiError.NoApiKey()
        val recent = history.takeLast(3).joinToString("; ") { h ->
            "${h.date} ${h.plan.sessionType} RPE ${h.fin?.rpe?.toString() ?: "?"}${if (h.fin?.pain?.isNotEmpty() == true) " pain: ${h.fin.pain}" else ""}"
        }
        val plan = todayPlan?.let { t ->
            "${t.plan.sessionType} — ${t.plan.exercises.joinToString(", ") { it.name }}${if (t.finished) " (finished)" else " (in progress)"}"
        } ?: "none generated yet"
        val trend = Stats.healthTrend(healthLog, 4)

        var system = "${coachRules()}\nYou are now CHATTING with the athlete (often mid-workout, phone in hand). Answer in 2-5 short sentences, plain text, no markdown, immediately practical. If they mention pain, be conservative and suggest the safe variation.\n"
        system += "CONTEXT — today's session: $plan. Recent: ${recent.ifEmpty { "no logged sessions" }}."
        if (trend.isNotEmpty()) system += "\nWatch data:\n$trend"
        if (focusSession != null) system += "\nFOCUS — the athlete is viewing this logged session and asking about it:\n${sessionDetail(focusSession)}"

        val contents = messages.takeLast(12).map { o("role" to if (it.role == "user") "user" else "model", "parts" to listOf(o("text" to it.text))) }

        var lastErr: Exception = GeminiError.Message("no models tried")
        for (model in models.take(2)) {
            val config = linkedMapOf<String, Any?>("maxOutputTokens" to 1500, "temperature" to 0.6)
            if (supportsThinkingLevel(model)) config["thinkingConfig"] = mapOf("thinkingLevel" to "minimal")
            try {
                val text = post(model, system, contents, j(config), 25)
                LocalStore.logEvent("coach_chat", mapOf("model" to JSONValue.Str(model), "chars" to JSONValue.Num(text.length.toDouble())))
                return text
            } catch (e: Exception) { if (e is CancellationException) throw e; lastErr = e }
        }
        throw lastErr
    }

    // ── "Make it harder" ─────────────────────────────────────────────

    data class IntensifyOption(val kind: String, val target: String, val why: String, val exercise: Plan.Exercise?)
    data class IntensifyResult(val note: String, val options: List<IntensifyOption>)

    private val intensifySchema = o(
        "type" to "OBJECT",
        "properties" to linkedMapOf(
            "note" to STR,
            "options" to mapOf(
                "type" to "ARRAY",
                "items" to linkedMapOf(
                    "type" to "OBJECT",
                    "properties" to linkedMapOf(
                        "kind" to mapOf("type" to "STRING", "enum" to listOf("add", "extraSet", "replace")),
                        "target" to STR,
                        "why" to STR,
                        "exercise" to linkedMapOf(
                            "type" to "OBJECT", "nullable" to true,
                            "properties" to linkedMapOf(
                                "name" to STR, "sets" to INT, "reps" to STR, "rpe" to STR, "rest" to STR,
                                "notes" to STR, "alt" to STR, "suggestedWeight" to STR,
                            ),
                            "required" to listOf("name", "sets", "reps"),
                        ),
                    ),
                    "required" to listOf("kind", "why"),
                ),
            ),
        ),
        "required" to listOf("options"),
    )

    suspend fun intensifyWorkout(today: Session, history: List<Session>, healthLog: List<HealthRow> = emptyList()): IntensifyResult {
        if (!Cloud.aiReady) throw GeminiError.NoApiKey()
        val p = today.plan
        val checkin = today.checkin
        val progress = p.exercises.mapIndexed { i, ex ->
            val done = (today.log.getOrNull(i) ?: emptyList()).filter { it.isLogged }.joinToString(", ") { it.formatted }
            "${i + 1}. ${ex.name} ${ex.sets}×${ex.reps}${if (ex.suggestedWeight.isEmpty()) "" else " @${ex.suggestedWeight}"} — sets logged: ${done.ifEmpty { "none yet" }}"
        }.joinToString("\n")

        val recovery = ArrayList<String>()
        val t = Stats.healthTrend(healthLog, 5)
        if (t.isNotEmpty()) recovery.add("Watch data trend:\n$t")
        val todayNums = Stats.parseHealthNumbers(checkin?.health)
        val base = Stats.healthBaseline(history, healthLog)
        if (todayNums.hrv != null && base.hrv != null) {
            val d = pct(todayNums.hrv, base.hrv)
            recovery.add("HRV today ${fmtKg(todayNums.hrv)} vs 30-day avg ${fmtKg(base.hrv)} (${signed(d)}%)")
        }
        if (todayNums.rhr != null && base.rhr != null) {
            val d = pct(todayNums.rhr, base.rhr)
            recovery.add("RHR today ${fmtKg(todayNums.rhr)} vs 30-day avg ${fmtKg(base.rhr)} (${signed(d)}%)")
        }
        Stats.fatigueSignal(history)?.let { recovery.add(it) }

        val recent = history.takeLast(3).joinToString("; ") { "${it.date} ${it.plan.sessionType} RPE ${it.fin?.rpe?.toString() ?: "?"}" }
        val equipment = LocalStore.backup.aiSettings.equipment.trim()
        val targets = Stats.progressionTargets(history)

        val userMsg = StringBuilder()
        userMsg.append("The athlete is mid-session TODAY and feels strong — they tapped \"make it harder\" and want to extend this workout.\n\n")
        userMsg.append("TODAY (${today.date}) — ${p.sessionType}, plan with live progress:\n$progress\n")
        userMsg.append("Time budget: ${checkin?.timeAvail ?: "60"} min gym time. Check-in this morning: energy ${checkin?.energy ?: 7}/10, sleep ${checkin?.sleep ?: "OK"}, soreness ${checkin?.soreness ?: "None"}${if (checkin?.soreAreas?.isNotEmpty() == true) " (${checkin.soreAreas})" else ""}.\n\n")
        userMsg.append("RECOVERY DATA (today vs their own history):\n${if (recovery.isEmpty()) "No watch data available — rely on check-in and training log." else recovery.joinToString("\n")}\n\n")
        userMsg.append("PROGRESSION TARGETS (from logged history):\n${targets.ifEmpty { "No logged sets yet." }}\n")
        userMsg.append("RECENT SESSIONS: ${recent.ifEmpty { "none logged" }}\n")
        if (equipment.isNotEmpty()) userMsg.append("GYM EQUIPMENT & LIMITS (never suggest anything unavailable):\n$equipment\n")
        userMsg.append("""
Offer 2-3 concrete ways to make today harder — AT MOST ONE of each kind:
- "add": ONE new exercise that fits the ${p.sessionType.ifEmpty { "current" }} split and the remaining time ("exercise" required, sets 2-3).
- "extraSet": one extra set on the existing exercise that would benefit most ("target" = its exact name from the plan).
- "replace": swap an exercise with NO sets logged yet for a harder variation ("target" = exact name of the exercise being replaced, "exercise" = the harder one). Skip this kind if everything is already started.
Keep "why" under 10 words. Anchor any suggestedWeight on the logged history — no big jumps.
"note": ONLY IF the recovery data above (sleep, HRV vs baseline, RHR, fatigue trend) suggests today isn't ideal for extra load, write ONE gentle supportive sentence reminding them of that specific data point — a soft nudge, never a prohibition, no scolding. If recovery looks fine, use an empty string.""")

        var lastErr: Exception = GeminiError.Message("no models tried")
        for (model in models.take(2)) {
            val config = linkedMapOf<String, Any?>("maxOutputTokens" to 2000, "temperature" to 0.5, "responseMimeType" to "application/json", "responseSchema" to intensifySchema)
            if (supportsThinkingLevel(model)) config["thinkingConfig"] = mapOf("thinkingLevel" to "low")
            try {
                val text = post(model, coachRules(), userContent(userMsg.toString()), j(config), 25)
                val obj = JSONValue.parse(text)?.obj ?: throw GeminiError.Message("could not parse intensify response")
                val note = obj["note"]?.string ?: ""
                val names = p.exercises.map { it.name.trim().lowercase() }.toSet()
                val options = ArrayList<IntensifyOption>()
                for (raw in obj["options"]?.array?.mapNotNull { it.obj } ?: emptyList()) {
                    val kind = raw["kind"]?.string ?: continue
                    val target = raw["target"]?.string ?: ""
                    val why = raw["why"]?.string ?: ""
                    var exercise: Plan.Exercise? = null
                    val exObj = raw["exercise"]?.obj
                    val name = exObj?.get("name")?.string
                    if (exObj != null && !name.isNullOrEmpty()) {
                        exercise = Plan.Exercise(
                            name = name, sets = exObj["sets"]?.number?.toInt() ?: 3, reps = exObj["reps"]?.string ?: "",
                            rpe = exObj["rpe"]?.string ?: "7-8", rest = exObj["rest"]?.string ?: "90s",
                            notes = exObj["notes"]?.string ?: "", alt = exObj["alt"]?.string ?: "",
                            suggestedWeight = exObj["suggestedWeight"]?.string ?: "",
                        )
                    }
                    val valid = when (kind) {
                        "add" -> exercise != null
                        "replace" -> exercise != null && target.trim().lowercase() in names
                        "extraSet" -> target.trim().lowercase() in names
                        else -> false
                    }
                    if (!valid) continue
                    exercise = exercise?.let { capSuggestedWeight(it, history) ?: it }
                    options.add(IntensifyOption(kind, target, why, exercise))
                    if (options.size >= 3) break
                }
                LocalStore.logEvent("ai_intensify", mapOf(
                    "model" to JSONValue.Str(model), "options" to JSONValue.Arr(options.map { JSONValue.Str(it.kind) }),
                    "hasNote" to JSONValue.Bool(note.isNotEmpty()),
                ))
                return IntensifyResult(note, options)
            } catch (e: Exception) { if (e is CancellationException) throw e; lastErr = e }
        }
        throw lastErr
    }

    // ── Debrief / weekly / monthly ───────────────────────────────────

    suspend fun generateDebrief(session: Session, history: List<Session>): String {
        val sets = session.plan.exercises.mapIndexed { i, ex ->
            val done = (session.log.getOrNull(i) ?: emptyList()).filter { it.isLogged }.joinToString(", ") { it.formatted }
            "${ex.name} [${done.ifEmpty { "skipped" }}]"
        }.joinToString("; ")
        val prev = history.takeLast(3).joinToString("; ") { "${it.date} ${it.plan.sessionType} RPE ${it.fin?.rpe?.toString() ?: "?"}" }
        val fin = session.fin
        val msg = "The athlete just finished today's session. Give a debrief: EXACTLY 2 short sentences — one on what went well, one on what you'll adjust next time. Plain text, no markdown, max 45 words total. Direct, no hype.\n\n" +
            "TODAY (${session.date}, ${session.plan.sessionType}): $sets\n" +
            "Session RPE ${fin?.rpe?.toString() ?: "?"}${if (fin?.pain?.isNotEmpty() == true) " | pain: ${fin.pain}" else ""}${if (fin?.feedback?.isNotEmpty() == true) " | athlete says: ${fin.feedback}" else ""}\n" +
            "RECENT: ${prev.ifEmpty { "first logged session" }}"
        return callGeminiText(msg, 120, "ai_debrief")
    }

    suspend fun generateWeeklyReview(summary: Stats.WeekSummary): String {
        val msg = "Write the athlete's weekly review: EXACTLY 2-3 short sentences — how the week went (sessions, progressions) and one concrete nudge for next week. Plain text, no markdown, max 55 words. Direct, no hype.\n\n" +
            "THIS WEEK: ${summary.count} sessions\n${summary.lines}\nLIFTS THAT MOVED UP: ${summary.progressions}"
        return callGeminiText(msg, 140, "ai_weekly_review")
    }

    suspend fun generateMonthlyReport(s: Stats.MonthSummary): String {
        fun line(label: String, cur: Double?, prev: Double? = null, unit: String = ""): String {
            if (cur == null) return ""
            val priorTxt = prev?.let { " (prior month ${fmtKg(it)}$unit)" } ?: ""
            return "$label: ${fmtKg(cur)}$unit$priorTxt"
        }
        val msg = StringBuilder()
        msg.append("Write the athlete's MONTHLY report for ${s.month}: EXACTLY 3-5 short sentences, plain text, max 90 words. Cover: how the month went (sessions, volume, lifts that moved), what the recovery data says (sleep/RHR/VO2max trends if present), and ONE concrete focus for next month. Honest and specific, no hype, no markdown.\n\n")
        msg.append("FACTS:\n")
        msg.append("Sessions: ${s.count}${if (s.prevCount > 0) " (prior month ${s.prevCount})" else ""} — split: ${s.split}\n")
        msg.append("Total volume: ${s.volume}kg${if (s.prevVolume > 0) " (prior ${s.prevVolume}kg)" else ""}\n")
        msg.append("Lifts that moved up: ${s.progressions}\n")
        for (l in listOf(line("Avg session RPE", s.avgRpe), line("Avg sleep", s.sleepAvg, s.sleepPrev, "h"), line("Avg resting HR", s.rhrAvg, s.rhrPrev), line("Avg HRV", s.hrvAvg, null, "ms"), line("VO2max", s.vo2Avg, s.vo2Prev))) {
            if (l.isNotEmpty()) msg.append(l + "\n")
        }
        if (s.weightStart != null && s.weightEnd != null) msg.append("Bodyweight: ${fmtKg(s.weightStart)} → ${fmtKg(s.weightEnd)}kg\n")
        return callGeminiText(msg.toString(), 220, "ai_monthly_report")
    }

    // ── Public entry point: generate with model fallback + retry ─────

    suspend fun generateWorkoutPlan(checkin: Checkin, history: List<Session>, template: SavedWorkout? = null, onStatus: ((String) -> Unit)? = null): Plan {
        val healthLog = LocalStore.backup.health
        // Errors from models we fell back past — surfaced with the final error so
        // a failing fallback (e.g. a retired model's 404) can't hide the real cause.
        val failures = ArrayList<String>()
        for ((mi, model) in models.withIndex()) {
            try {
                if (mi > 0) onStatus?.invoke("Trying $model…")
                return callGemini(checkin, history, model, healthLog, template)
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                if (error is GeminiError.NoConsent || error is GeminiError.Server) throw error // another model won't help
                val last = mi == models.size - 1
                if (error is GeminiError.Overloaded && !last) {
                    failures.add("$model: overloaded")
                    onStatus?.invoke("$model is busy — switching model…")
                    delay(1000)
                    continue
                }
                // rate limited — each model has its own quota, so switch
                // first; only the last model waits and retries
                if (error is GeminiError.RateLimited && !last) {
                    failures.add("$model: rate limited")
                    onStatus?.invoke("$model is at its limit — switching model…")
                    continue
                }
                if (error is GeminiError.RateLimited) {
                    for (s in error.retryDelay downTo 1) {
                        onStatus?.invoke("Rate limited — retrying in ${s}s…")
                        delay(1000)
                    }
                    try {
                        return callGemini(checkin, history, model, healthLog, template)
                    } catch (retryErr: Exception) {
                        if (retryErr is GeminiError.RateLimited) throw GeminiError.Message("Rate limit hit twice. Wait a minute and try again.")
                        throw retryErr
                    }
                }
                val message = error.message ?: error.toString()
                if (!last) {
                    failures.add("$model: $message")
                    continue
                }
                if (failures.isNotEmpty()) throw GeminiError.Message("$model: $message\n\nEarlier attempts — ${failures.joinToString(" · ")}")
                throw error
            }
        }
        throw GeminiError.Message("Couldn't build today's session. Check Settings for your API key, then try again.")
    }

    // ── Saved workouts: built from a trainer's program, a photo of one, or a description ──

    private val workoutsSchema = o(
        "type" to "OBJECT",
        "properties" to linkedMapOf(
            "workouts" to mapOf(
                "type" to "ARRAY",
                "items" to linkedMapOf(
                    "type" to "OBJECT",
                    "properties" to linkedMapOf(
                        "name" to STR,
                        "kind" to mapOf("type" to "STRING", "enum" to listOf("session", "addon")),
                        "days" to mapOf("type" to "ARRAY", "items" to mapOf("type" to "STRING", "enum" to listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"))),
                        "notes" to STR,
                        "exercises" to mapOf(
                            "type" to "ARRAY",
                            "items" to linkedMapOf(
                                "type" to "OBJECT",
                                "properties" to linkedMapOf(
                                    "name" to STR, "sets" to INT, "reps" to STR, "weight" to STR, "rest" to STR, "notes" to STR,
                                ),
                                "required" to listOf("name", "sets", "reps"),
                            ),
                        ),
                    ),
                    "required" to listOf("name", "kind", "exercises"),
                ),
            ),
            "message" to STR,
        ),
        "required" to listOf("workouts"),
    )

    data class BuiltWorkouts(val workouts: List<SavedWorkout>, val message: String)

    /** Turns what the athlete gave — a trainer's program (text and/or a JPEG
     *  photo of it) or a description — into saved-workout drafts to review
     *  (buildWorkouts in gemini.js). Nothing is saved here. */
    suspend fun buildWorkouts(text: String, imageJPEG: ByteArray?, source: String, history: List<Session>): BuiltWorkouts {
        if (!Cloud.aiReady) throw GeminiError.Message("Add your Gemini API key in Settings first — the coach builds workouts with it.")
        val settings = LocalStore.backup.aiSettings
        val known = LinkedHashSet<String>()
        for (s in history) for (e in s.plan.exercises) { val n = e.name.trim(); if (n.isNotEmpty()) known.add(n) }
        val knownList = known.take(80)
        val trainer = source == "trainer"
        val msg = StringBuilder("Turn the athlete's input into saved workouts for their training app.\n\n")
        msg.append(
            if (trainer) "This is a program the athlete's personal trainer wrote. Transcribe it faithfully: keep every exercise, set, rep, weight, rest and note exactly as written — never add, drop or 'improve' anything. If something is illegible or ambiguous, make the most likely reading and mention it in \"message\"."
            else "If this is a written program, transcribe it faithfully. If it's a description of what they want (e.g. '20 minutes of core every day', 'upper body with dumbbells, 45 min'), design it: sensible exercises, sets, reps and rest for their goals, equipment and history."
        )
        msg.append("""


Rules:
- One workout per training day. A multi-day program (Day A/B/C, Monday/Wednesday…) becomes several workouts; put the weekdays in "days" ONLY when the input names them (or says "every day" → all seven).
- kind "addon" for a short routine meant to be added on top of sessions (core finisher, stretching, mobility, warm-up, "every day" habit); otherwise "session".
- name: short, e.g. "Upper A", "Leg day", "Daily core". Use the input's own day names when it has them.
- Exercise names: common English gym names. When the exercise is one of the athlete's KNOWN EXERCISES below, use that exact name so their progress links up. Expand abbreviations (DB → Dumbbell, BB → Barbell, RDL → Romanian Deadlift).
- reps: as written, e.g. "8-10", "12", "45s", "AMRAP". weight: as written, e.g. "20kg", "bodyweight", or "" if none. rest: e.g. "90s", "2 min", or "".
- notes: tempo, cues or instructions from the input, else "".
- "message": one short sentence for the athlete — what you built, plus anything you had to guess.

KNOWN EXERCISES: ${if (knownList.isEmpty()) "none yet" else knownList.joinToString(", ")}
""")
        val equipment = settings.equipment.trim()
        val goals = settings.goals.trim()
        if (equipment.isNotEmpty()) msg.append("EQUIPMENT & LIMITS: $equipment\n")
        if (goals.isNotEmpty()) msg.append("GOALS: $goals\n")
        msg.append("\nATHLETE'S INPUT:\n${if (text.trim().isEmpty()) "(see the attached photo)" else text}")

        val parts = ArrayList<JSONValue>()
        parts.add(o("text" to msg.toString()))
        if (imageJPEG != null) parts.add(o("inline_data" to o("mime_type" to "image/jpeg", "data" to Base64.getEncoder().encodeToString(imageJPEG))))

        var lastErr: Exception = GeminiError.Message("no models tried")
        for (model in models.take(2)) {
            val config = linkedMapOf<String, Any?>("maxOutputTokens" to 6000, "temperature" to if (trainer) 0.2 else 0.6, "responseMimeType" to "application/json", "responseSchema" to workoutsSchema)
            if (supportsThinkingLevel(model)) config["thinkingConfig"] = mapOf("thinkingLevel" to "low")
            try {
                val out = post(model, coachRules(), listOf(o("role" to "user", "parts" to parts)), j(config), 60)
                val obj = JSONValue.parse(out)?.obj ?: throw GeminiError.Message("The coach's reply couldn't be read — try again.")
                val dayIdx = mapOf("Sun" to 0, "Mon" to 1, "Tue" to 2, "Wed" to 3, "Thu" to 4, "Fri" to 5, "Sat" to 6)
                val workouts = (obj["workouts"]?.array ?: emptyList()).mapNotNull { it.obj }.mapNotNull { w ->
                    val ex = (w["exercises"]?.array ?: emptyList()).mapNotNull { it.obj }.map { e ->
                        SavedWorkout.Exercise(
                            name = e["name"]?.string ?: "", sets = (e["sets"]?.number?.toInt() ?: 3).coerceIn(1, 10),
                            reps = e["reps"]?.string ?: "", weight = e["weight"]?.string ?: "",
                            rest = e["rest"]?.string ?: "", notes = e["notes"]?.string ?: "",
                        )
                    }
                    if (ex.isEmpty()) return@mapNotNull null
                    SavedWorkout(
                        name = w["name"]?.string ?: "Workout", kind = if (w["kind"]?.string == "addon") "addon" else "session",
                        source = source, notes = w["notes"]?.string ?: "",
                        days = (w["days"]?.array ?: emptyList()).mapNotNull { d -> d.string?.let { dayIdx[it] } }, exercises = ex,
                    )
                }
                val message = obj["message"]?.string ?: ""
                if (workouts.isEmpty()) throw GeminiError.Message(message.ifEmpty { "The coach couldn't find a workout in that — add a bit more detail." })
                LocalStore.logEvent("ai_build_workouts", mapOf(
                    "model" to JSONValue.Str(model), "source" to JSONValue.Str(source), "image" to JSONValue.Bool(imageJPEG != null),
                    "workouts" to JSONValue.Num(workouts.size.toDouble()),
                ))
                return BuiltWorkouts(workouts, message)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                lastErr = e
            }
        }
        throw lastErr
    }

}
