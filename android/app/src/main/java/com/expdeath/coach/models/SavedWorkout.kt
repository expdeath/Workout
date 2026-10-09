package com.expdeath.coach.models

import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.stats.rounded
import com.expdeath.coach.sync.Cloud
import java.time.LocalDate
import java.util.UUID

/** A saved workout — the athlete's own or their trainer's (the shape in
 *  src/utils/workouts.js). Stored as account state `workout-<id>` in
 *  Firestore, so the library, weekday schedule and daily add-ons are the
 *  same on the web, iPhone and here. */
data class SavedWorkout(
    val id: String = "",
    val name: String = "",
    /** "session" | "addon" — an add-on rides along on the day's session. */
    val kind: String = "session",
    /** "me" | "trainer" */
    val source: String = "me",
    val trainer: String = "",
    val notes: String = "",
    /** Session only: let the coach adapt it to today (off = kept exactly as written). */
    val adapt: Boolean = false,
    /** Weekdays, 0 = Sunday … 6 = Saturday. An add-on with none runs every day. */
    val days: List<Int> = emptyList(),
    val exercises: List<Exercise> = emptyList(),
    val createdAt: Double = 0.0,
    val updatedAt: Double = 0.0,
) {
    data class Exercise(
        val name: String = "",
        val sets: Int = 3,
        val reps: String = "10",
        val weight: String = "",
        val rest: String = "",
        val notes: String = "",
    ) {
        fun toJson(): JSONValue = jobj {
            put("name", name); put("sets", sets); put("reps", reps); put("weight", weight); put("rest", rest); put("notes", notes)
        }

        companion object {
            fun fromJson(v: JSONValue): Exercise? {
                val c = v.obj ?: return null
                return Exercise(
                    name = c.lenientString("name") ?: "",
                    sets = c.lenientInt("sets") ?: 3,
                    reps = c.lenientString("reps") ?: "10",
                    weight = c.lenientString("weight") ?: "",
                    rest = c.lenientString("rest") ?: "",
                    notes = c.lenientString("notes") ?: "",
                )
            }
        }
    }

    val isAddOn: Boolean get() = kind == "addon"

    fun toJson(): JSONValue = jobj {
        put("id", id); put("name", name); put("kind", kind); put("source", source); put("trainer", trainer)
        put("notes", notes); put("adapt", adapt)
        put("days", JSONValue.Arr(days.map { JSONValue.Num(it.toDouble()) }))
        put("exercises", JSONValue.Arr(exercises.map { it.toJson() }))
        put("createdAt", createdAt); put("updatedAt", updatedAt)
    }

    companion object {
        fun fromJson(v: JSONValue): SavedWorkout? {
            val c = v.obj ?: return null
            return SavedWorkout(
                id = c.lenientString("id") ?: "",
                name = c.lenientString("name") ?: "",
                kind = if (c.lenientString("kind") == "addon") "addon" else "session",
                source = if (c.lenientString("source") == "trainer") "trainer" else "me",
                trainer = c.lenientString("trainer") ?: "",
                notes = c.lenientString("notes") ?: "",
                adapt = c.lenientBool("adapt") ?: false,
                days = c.lenientList("days") { d -> d.number?.takeIf { it == Math.rint(it) }?.toInt() } ?: emptyList(),
                exercises = c.lenientList("exercises", Exercise::fromJson) ?: emptyList(),
                createdAt = c.lenientDouble("createdAt") ?: 0.0,
                updatedAt = c.lenientDouble("updatedAt") ?: 0.0,
            )
        }
    }
}

/** The saved-workout library (port of src/utils/workouts.js): list, save,
 *  schedule, and turning a workout into today's plan. */
object Workouts {
    private const val PREFIX = "workout-"
    val weekdays = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    /** Display order: Monday first. */
    val weekOrder = listOf(1, 2, 3, 4, 5, 6, 0)

    fun list(): List<SavedWorkout> =
        Cloud.stateKeys().filter { it.startsWith(PREFIX) }
            .mapNotNull { get(it.removePrefix(PREFIX)) }
            .sortedWith(compareBy<SavedWorkout> { it.isAddOn }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    fun get(id: String?): SavedWorkout? {
        if (id.isNullOrEmpty()) return null
        val v = Cloud.stateValue(PREFIX + id) ?: return null
        return SavedWorkout.fromJson(v)?.takeIf { it.id.isNotEmpty() }
    }

    /** Cleans and stores a workout; returns what was saved. */
    fun save(w: SavedWorkout): SavedWorkout {
        val now = nowMs().rounded()
        val clean = w.copy(
            id = w.id.ifEmpty { now.toLong().toString(36) + UUID.randomUUID().toString().take(4).lowercase() },
            name = w.name.trim().ifEmpty { "My workout" },
            trainer = w.trainer.trim(),
            notes = w.notes.trim(),
            adapt = if (w.isAddOn) false else w.adapt,
            days = w.days.filter { it in 0..6 }.toSet().sorted(),
            exercises = w.exercises.filter { it.name.trim().isNotEmpty() }.map { e ->
                e.copy(
                    name = e.name.trim(),
                    sets = e.sets.coerceIn(1, 10),
                    reps = e.reps.trim().ifEmpty { "10" },
                    weight = e.weight.trim(), rest = e.rest.trim(), notes = e.notes.trim(),
                )
            },
            createdAt = if (w.createdAt == 0.0) now else w.createdAt,
            updatedAt = now,
        )
        Cloud.setState(PREFIX + clean.id, clean.toJson())
        return clean
    }

    fun delete(id: String) = Cloud.setState(PREFIX + id, null)

    /** Raw state values — the backup file carries them as-is. */
    fun rawAll(): List<JSONValue> = Cloud.stateKeys().filter { it.startsWith(PREFIX) }.sorted().mapNotNull { Cloud.stateValue(it) }

    /** 0 = Sunday … 6 = Saturday. */
    private fun weekday(iso: String): Int {
        val d = Helpers.parseDate(iso) ?: LocalDate.now(Helpers.zone)
        return d.dayOfWeek.value % 7
    }

    data class Scheduled(val sessions: List<SavedWorkout>, val addOns: List<SavedWorkout>)

    /** Session workouts scheduled on `date`'s weekday, and the add-ons that run that day. */
    fun scheduledFor(date: String = Helpers.todayStr(), all: List<SavedWorkout> = list()): Scheduled {
        val wd = weekday(date)
        return Scheduled(
            all.filter { !it.isAddOn && wd in it.days },
            all.filter { it.isAddOn && (it.days.isEmpty() || wd in it.days) },
        )
    }

    /** "Mon · Wed · Fri", "Every day", or "" (not scheduled). */
    fun daysLabel(w: SavedWorkout): String {
        if (w.days.isEmpty()) return if (w.isAddOn) "Every day" else ""
        if (w.days.size == 7) return "Every day"
        return weekOrder.filter { it in w.days }.joinToString(" · ") { weekdays[it] }
    }

    /** A plan exercise from a saved one: its own weight, else the next step
     *  from the logged history. */
    private fun planExercise(e: SavedWorkout.Exercise, history: List<Session>, note: String = ""): Plan.Exercise {
        var w = e.weight
        if (w.isEmpty()) {
            val last = Stats.lastPerformance(history, e.name)
            val next = Stats.suggestNextWeight(last, e.reps)
            val top = last?.sets?.mapNotNull { parseDouble(it.weight) }?.maxOrNull()
            if (next != null) w = "${Helpers.fmtKg(next)}kg"
            else if (top != null && top > 0) w = "${Helpers.fmtKg(top)}kg"
        } else if (parseDouble(w) != null) {
            w += "kg"
        }
        return Plan.Exercise(
            name = e.name, sets = e.sets, reps = e.reps, rpe = "", rest = e.rest.ifEmpty { "90s" },
            notes = listOf(note, e.notes).filter { it.isNotEmpty() }.joinToString(" · "), alt = "", suggestedWeight = w, superset = "",
        )
    }

    /** { id, name, source, trainer, adapt } — which saved workout a plan came from. */
    fun fromWorkout(w: SavedWorkout, adapt: Boolean): JSONValue = jobj {
        put("id", w.id); put("name", w.name); put("source", w.source); put("trainer", w.trainer); put("adapt", adapt)
    }

    private fun guessType(w: SavedWorkout): String {
        val n = (w.name + " " + w.exercises.joinToString(" ") { it.name }).lowercase()
        fun has(p: String) = Regex(p).containsMatchIn(n)
        val lifts = has("press|squat|curl|deadlift")
        if (has("stretch|mobility|yoga")) return "Stretch & Mobility"
        if (has("run|cycle|bike|row|cardio|walk") && !lifts) return "Cardio"
        if (has("core|abs|plank") && !lifts && !has("row")) return "Core"
        if (has("push|chest") && !has("pull|leg")) return "Push"
        if (has("pull|back") && !has("push|leg")) return "Pull"
        if (has("leg|squat|lower") && !has("push|pull|upper")) return "Legs"
        return "Full Body"
    }

    /** Without the AI (no key, offline, coach failed): exactly as written. */
    fun templateToPlan(w: SavedWorkout, history: List<Session>): Plan {
        val ex = w.exercises.map { planExercise(it, history) }
        return Plan(
            sessionType = guessType(w), title = w.name, recoveryScore = null,
            reasoning = if (w.source == "trainer") "${w.trainer.ifEmpty { "Your trainer" }}'s workout, as written." else "Your saved workout, as written.",
            exercises = ex, estTimeMin = (ex.sumOf { it.sets } * 2.5).rounded().toInt().takeIf { it != 0 } ?: 30,
            fromWorkout = fromWorkout(w, w.adapt),
        )
    }

    /** Keep-exact mode: the coach may only add weights, cues and warnings. */
    fun enforceExact(ai: Plan, w: SavedWorkout, history: List<Session>): Plan {
        val byName = LinkedHashMap<String, Plan.Exercise>()
        for (e in ai.exercises) byName.putIfAbsent(e.name.trim().lowercase(), e)
        return ai.copy(
            title = w.name,
            exercises = w.exercises.mapIndexed { i, e ->
                val base = planExercise(e, history)
                val c = byName[e.name.lowercase()] ?: ai.exercises.getOrNull(i) ?: Plan.Exercise()
                base.copy(
                    rpe = c.rpe,
                    suggestedWeight = if (e.weight.isEmpty() && c.suggestedWeight.isNotEmpty()) c.suggestedWeight else base.suggestedWeight,
                    notes = listOf(e.notes, if (c.notes != e.notes) c.notes else "").filter { it.isNotEmpty() }.joinToString(" · "),
                    alt = c.alt,
                )
            },
            fromWorkout = fromWorkout(w, false),
        )
    }

    /** Today's add-ons go on the end of the session. */
    fun appendAddOns(plan: Plan, addOns: List<SavedWorkout>, history: List<Session>): Plan {
        if (addOns.isEmpty()) return plan
        val extra = addOns.flatMap { a -> a.exercises.map { planExercise(it, history, "Add-on · ${a.name}") } }
        return plan.copy(exercises = plan.exercises + extra, estTimeMin = plan.estTimeMin + extra.sumOf { it.sets * 2 })
    }

    /** The workout as a brief for the coach's prompt (workoutBrief in workouts.js). */
    fun brief(w: SavedWorkout): String {
        val who = if (w.source == "trainer") "written by the athlete's trainer${if (w.trainer.isEmpty()) "" else " (${w.trainer})"}" else "saved by the athlete"
        val lines = w.exercises.mapIndexed { i, e ->
            "${i + 1}. ${e.name} — ${e.sets} × ${e.reps}${if (e.weight.isEmpty()) "" else " @ ${e.weight}"}${if (e.rest.isEmpty()) "" else ", rest ${e.rest}"}${if (e.notes.isEmpty()) "" else " (${e.notes})"}"
        }
        return "\"${w.name}\", $who${if (w.notes.isEmpty()) "" else " — notes: ${w.notes}"}:\n" + lines.joinToString("\n")
    }
}
