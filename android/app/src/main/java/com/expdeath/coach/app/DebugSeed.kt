package com.expdeath.coach.app

import android.content.Intent
import com.expdeath.coach.account.Account
import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.FinishInfo
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.SavedWorkout
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.models.toJson
import com.expdeath.coach.persistence.AIConsent
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.fmt
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.sync.Cloud
import java.time.LocalDate
import kotlin.math.sin

/** Debug-build seeding for screenshots/UI checks without a real Google
 *  sign-in (port of DebugSeed.swift). Runs fully offline (Cloud.offline —
 *  nothing reaches Firestore) with a fake account. Triggered by intent
 *  extras, e.g.
 *    adb shell am start -n com.expdeath.coach/.app.MainActivity --es COACH_DEBUG_SEED 1 --es COACH_DEBUG_SCREEN workout
 *  Ignored in release builds (MainActivity checks BuildConfig.DEBUG). */
object DebugSeed {
    private fun screenFor(name: String?): Screen? = when (name) {
        "checkIn" -> Screen.CheckIn
        "generating" -> Screen.Generating
        "workout" -> Screen.Workout
        "finish" -> Screen.Finish
        "history" -> Screen.History
        "records" -> Screen.Records
        "progress" -> Screen.Progress
        "settings" -> Screen.Settings
        "workouts" -> Screen.Workouts
        else -> null
    }

    /** Returns the screen to boot onto (or null for the normal start). */
    fun applyIfRequested(intent: Intent?): Screen? {
        if (intent?.getStringExtra("COACH_DEBUG_SEED") != "1") return null
        val start = screenFor(intent.getStringExtra("COACH_DEBUG_SCREEN"))
        Account.wipeLocal()
        Cloud.debugActivate(Cloud.AccountInfo("preview", "Preview", false, "preview@example.invalid"), "debug-not-a-real-key")
        // the screenshot account has already said yes to the AI coach
        if (intent.getStringExtra("COACH_DEBUG_CONSENT") != "ask") AIConsent.set(true)

        val plan = Plan(
            sessionType = "Push", title = "Push Day", recoveryScore = 78,
            reasoning = "Solid recovery, ready to push volume.", warmup = listOf("10min bike easy"),
            exercises = listOf(
                Plan.Exercise(name = "Flat Dumbbell Press", sets = 3, reps = "10-12", rpe = "7-8", rest = "90s", suggestedWeight = "24kg"),
                Plan.Exercise(name = "Incline Machine Press", sets = 3, reps = "10-12", rpe = "7-8", rest = "90s"),
            ),
            cooldown = listOf("doorway chest stretch"), estTimeMin = 52,
        )
        LocalStore.seed(Session(
            id = "2026-08-30#1", date = "2026-08-30", startedAt = 0.0, checkin = null, plan = plan,
            log = listOf(listOf(SetLog(weight = "24", reps = "11", done = true)), listOf(SetLog(weight = "20", reps = "12", done = true))),
            finished = true, fin = FinishInfo(7, "", "Felt strong"),
            debrief = "Good pressing volume today — chest and shoulders both moved well. Next time, add a set to incline press since reps were easy across the board.",
        ))
        // a trainer's workout scheduled today + a daily add-on
        if (intent.getStringExtra("COACH_DEBUG_WORKOUTS") == "1") {
            val wd = LocalDate.now().dayOfWeek.value % 7
            Workouts.save(SavedWorkout(name = "Upper A", source = "trainer", trainer = "Sam", days = listOf(wd, (wd + 2) % 7), exercises = listOf(
                SavedWorkout.Exercise("Flat Dumbbell Press", 4, "6-8"),
                SavedWorkout.Exercise("Barbell Row", 3, "8", "60kg", "2 min"),
                SavedWorkout.Exercise("Lateral Raise", 3, "12-15", rest = "60s"),
            )))
            Workouts.save(SavedWorkout(name = "Lower B", source = "trainer", trainer = "Sam", adapt = true, days = listOf((wd + 1) % 7), exercises = listOf(
                SavedWorkout.Exercise("Back Squat", 4, "6", "85kg", "3 min"),
                SavedWorkout.Exercise("Romanian Deadlift", 3, "8"),
            )))
            Workouts.save(SavedWorkout(name = "Daily core", kind = "addon", exercises = listOf(
                SavedWorkout.Exercise("Plank", 3, "45s", rest = "30s"), SavedWorkout.Exercise("Dead Bug", 2, "10"),
            )))
        }
        // an in-progress session for the Workout/Finish screens: every logging mode
        if (start == Screen.Workout || start == Screen.Finish) {
            val today = Plan(
                sessionType = "Push", title = "Chest & shoulders", recoveryScore = 74,
                reasoning = "Good sleep, low soreness — a full push day.", warmup = listOf("5min row easy"),
                exercises = listOf(
                    Plan.Exercise("Flat Dumbbell Press", 2, "8-12", "8", "90s", "Control the eccentric.", "Machine Chest Press", "24kg"),
                    Plan.Exercise("Lateral Raise", 2, "12-15", "8", "60s", superset = "A"),
                    Plan.Exercise("Cable Triceps Pushdown", 2, "12", "8", "60s", superset = "A"),
                    Plan.Exercise("Incline Walk", 1, "10min", "6", "0s"),
                    Plan.Exercise("Doorway Chest Stretch", 1, "30s each side", "", "0s"),
                ),
                cooldown = listOf("easy breathing 1min"), estTimeMin = 55,
            )
            val t = Session(
                id = "${Helpers.todayStr()}#1", date = Helpers.todayStr(), startedAt = System.currentTimeMillis() - 40 * 60000.0,
                checkin = Checkin(), plan = today, log = today.exercises.map { e -> List(e.sets) { SetLog() } },
            )
            Cloud.setState("today", t.toJson())
        }
        // today's Watch row → check-in shows "Watch data loaded" with details open
        LocalStore.mergeHealth(HealthRow(Helpers.todayStr(), hrv = 52.0, rhr = 57.0, raw = "Sleep 7h10m · HRV 52 · RHR 57 · Steps 8400"))
        if (intent.getStringExtra("COACH_DEBUG_RICH") == "1") seedRich()
        return start
    }

    /** Eight weeks of push/pull/legs + walks with slowly rising weights and
     *  daily Watch rows — enough for every dashboard card to show something. */
    private fun seedRich() {
        val lifts = mapOf(
            "Push" to listOf("Flat Dumbbell Press" to 20.0, "Incline Machine Press" to 30.0, "Cable Triceps Pushdown" to 18.0),
            "Pull" to listOf("Chest Supported Row" to 36.0, "Lat Pulldown" to 50.0, "Cable Curl" to 14.0),
            "Legs" to listOf("Leg Press" to 90.0, "Romanian Deadlift" to 40.0, "Leg Curl" to 30.0),
        )
        for (d in 1..56) {
            val dow = d % 7
            val type = if (dow == 1 || dow == 3 || dow == 5) listOf("Push", "Pull", "Legs")[(d / 2) % 3] else if (dow == 6) "Cardio" else continue
            val date = Helpers.daysAgoStr(d)
            val progress = (56 - d) / 56.0
            if (type == "Cardio") {
                val km = fmt("%.1f", 3 + progress * 2)
                val plan = Plan(sessionType = "Cardio", title = "Outdoor walk", exercises = listOf(Plan.Exercise(name = "Outdoor Walk", sets = 1, reps = "40min")))
                LocalStore.seed(Session("$date#9", date, 0.0, null, plan, listOf(listOf(SetLog(done = true, time = "45", dist = km))), true, FinishInfo(4), 45))
                continue
            }
            val exs = lifts.getValue(type)
            val plan = Plan(sessionType = type, title = "", exercises = exs.map { Plan.Exercise(name = it.first, sets = 3, reps = "8-12", rpe = "8") })
            val log = exs.map { ex ->
                val w = Helpers.fmtKg(((ex.second * (1 + 0.5 * progress)) / 2.5).rounded() * 2.5)
                (0 until 3).map { i -> SetLog(weight = w, reps = "${12 - i}", done = true) }
            }
            LocalStore.seed(Session("$date#1", date, 0.0, null, plan, log, true, FinishInfo(7), 60 + d % 4 * 5))
        }
        for (d in 1..30) {
            val wave = sin(d / 3.0)
            LocalStore.mergeHealth(HealthRow(Helpers.daysAgoStr(d), hrv = 48 + 6 * wave, rhr = 58 - 2 * wave, sleepH = 7 + 0.6 * wave, weightKg = 78 - (30 - d) * 0.05))
        }
        LocalStore.mergeHealth(HealthRow(Helpers.todayStr(), hrv = 56.0, rhr = 55.0, sleepH = 7.6))
    }
}
