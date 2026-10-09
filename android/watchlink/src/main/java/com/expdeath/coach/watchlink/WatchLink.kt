package com.expdeath.coach.watchlink

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** The phone ↔ watch protocol — docs/watch.md is the spec, and
 *  ios/CoachApp/Shared/WatchLink.swift (ios branch) is the same thing in
 *  Swift, so a COACH watch speaks the same JSON on either platform.
 *
 *  The phone owns the workout: it sends a [WatchState] snapshot whenever
 *  today's session or the rest timer changes, and the watch sends back
 *  small [WatchCommand]s ("set 2 done: 60 kg × 8"). The watch applies its
 *  own commands to the last snapshot straight away ([WatchState.applying]),
 *  so the wrist never waits on Bluetooth; the phone's next snapshot lists
 *  the command ids it has applied ([WatchState.acks]) and replaces the
 *  guess. */
object WatchPaths {
    const val VERSION = 1
    /** Phone → watch: the latest [WatchState] (a Data Layer item). */
    const val STATE = "/coach/state"
    /** Watch → phone: one Data Layer item per command, `/coach/cmd/<id>`. */
    const val COMMAND = "/coach/cmd"
    /** Capabilities each side advertises (res/values/wear.xml). */
    const val PHONE_CAPABILITY = "coach_phone"
    const val WATCH_CAPABILITY = "coach_watch"
}

/** One set as the watch sees it. w/r/t/d are what's logged (strings, like
 *  SetLog); pw/pr/pt are the greyed hints the phone shows in an empty
 *  field — the suggested weight, last time's reps/minutes. */
data class WSet(
    val w: String = "", val r: String = "", val t: String = "", val d: String = "",
    val done: Boolean = false, val e: String = "",
    val pw: String = "", val pr: String = "", val pt: String = "",
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("w", w); put("r", r); put("t", t); put("d", d); put("done", done); put("e", e)
        put("pw", pw); put("pr", pr); put("pt", pt)
    }

    companion object {
        fun fromJson(o: JsonObject) = WSet(
            w = o.str("w"), r = o.str("r"), t = o.str("t"), d = o.str("d"), done = o.bool("done"), e = o.str("e"),
            pw = o.str("pw"), pr = o.str("pr"), pt = o.str("pt"),
        )
    }
}

/** mode: "strength" (kg × reps) · "cardio" (min / km) · "check" (tick only) —
 *  Stats.logMode on the phone decides. */
data class WExercise(
    val name: String,
    val mode: String = "strength",
    val reps: String = "",
    val rpe: String = "",
    val restSec: Int = 90,
    /** What to try today ("62.5") — the suggestion the phone shows in amber. */
    val target: String = "",
    /** Last time, formatted ("60kg×8, 60kg×8"). */
    val last: String = "",
    val superset: String = "",
    val sets: List<WSet> = emptyList(),
) {
    val doneSets: Int get() = sets.count { it.done }

    fun toJson(): JsonObject = buildJsonObject {
        put("name", name); put("mode", mode); put("reps", reps); put("rpe", rpe); put("restSec", restSec)
        put("target", target); put("last", last); put("superset", superset)
        put("sets", JsonArray(sets.map { it.toJson() }))
    }

    companion object {
        fun fromJson(o: JsonObject) = WExercise(
            name = o.str("name"), mode = o.str("mode").ifEmpty { "strength" }, reps = o.str("reps"), rpe = o.str("rpe"),
            restSec = o.long("restSec")?.toInt() ?: 90, target = o.str("target"), last = o.str("last"),
            superset = o.str("superset"),
            sets = (o["sets"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(WSet::fromJson) } ?: emptyList(),
        )
    }
}

/** The running rest timer. endsAt is epoch ms — both devices keep network time. */
data class WRest(val endsAt: Long, val total: Int, val ex: String) {
    fun toJson(): JsonObject = buildJsonObject { put("endsAt", endsAt); put("total", total); put("ex", ex) }

    companion object {
        fun fromJson(o: JsonObject): WRest? {
            val end = o.long("endsAt") ?: return null
            return WRest(end, o.long("total")?.toInt() ?: 90, o.str("ex"))
        }
    }
}

/** Where to go next: an exercise and a set in it. */
data class WFocus(val ex: Int, val set: Int)

/** What the watch pre-fills for a set: what's logged, else the set before
 *  it today, else the phone's hint. */
data class WPrefill(val w: String, val r: String, val t: String, val d: String)

data class WatchState(
    /** A workout is running on the phone (today's session, not finished). */
    val active: Boolean = false,
    val id: String = "",
    val type: String = "",
    val title: String = "",
    val startedAt: Long = 0,
    val exercises: List<WExercise> = emptyList(),
    val rest: WRest? = null,
    /** The last command ids the phone applied. */
    val acks: List<String> = emptyList(),
    /** The session was just finished (on either device) — the watch wraps up. */
    val finished: Boolean = false,
    val sentAt: Long = 0,
) {
    val doneSets: Int get() = exercises.sumOf { it.doneSets }
    val totalSets: Int get() = exercises.sumOf { it.sets.size }

    /** The web's superset flow (Workout.jsx renderedIdx): two exercises
     *  sharing a letter run as rounds A1 B1 A2 B2; everything else in plan
     *  order. The first set not done yet is next. */
    fun next(): WFocus? {
        for (g in groups(exercises)) {
            val rounds = g.maxOf { exercises[it].sets.size }
            for (r in 0 until rounds) for (i in g) {
                val s = exercises[i].sets.getOrNull(r) ?: continue
                if (!s.done) return WFocus(i, r)
            }
        }
        return null
    }

    /** The first set of this exercise not done yet (null: all done). */
    fun nextSet(ex: Int): Int? = exercises.getOrNull(ex)?.sets?.indexOfFirst { !it.done }?.takeIf { it >= 0 }

    fun prefill(ex: Int, set: Int): WPrefill {
        val e = exercises.getOrNull(ex) ?: return WPrefill("", "", "", "")
        val s = e.sets.getOrNull(set) ?: WSet()
        // the nearest earlier set logged today — the weight you just lifted
        val before = e.sets.take(set.coerceAtMost(e.sets.size)).lastOrNull { it.done || it.w.isNotEmpty() || it.r.isNotEmpty() || it.t.isNotEmpty() }
        fun pick(vararg v: String) = v.firstOrNull { it.isNotEmpty() } ?: ""
        return WPrefill(
            w = pick(s.w, before?.w ?: "", s.pw, e.target),
            r = pick(s.r, before?.r ?: "", s.pr, firstNumber(e.reps)),
            t = pick(s.t, before?.t ?: "", s.pt),
            d = pick(s.d, before?.d ?: ""),
        )
    }

    /** Which exercise a command means: its index when the name still
     *  matches (the plan can change on the phone mid-workout), else the
     *  exercise with that name. */
    fun exerciseIndex(cmd: WatchCommand): Int? {
        val byIndex = exercises.getOrNull(cmd.ex)
        if (byIndex != null && (cmd.name.isEmpty() || key(byIndex.name) == key(cmd.name))) return cmd.ex
        if (cmd.name.isEmpty()) return null
        return exercises.indexOfFirst { key(it.name) == key(cmd.name) }.takeIf { it >= 0 }
    }

    /** The watch's own guess of what the phone will do with `cmd` —
     *  the same edits AppState makes. */
    fun applying(cmd: WatchCommand): WatchState {
        if (cmd.session.isNotEmpty() && cmd.session != id) return this
        fun edit(f: (WExercise) -> WExercise?): WatchState {
            val i = exerciseIndex(cmd) ?: return this
            val n = f(exercises[i]) ?: return this
            return copy(exercises = exercises.mapIndexed { j, e -> if (j == i) n else e })
        }
        fun WExercise.editSet(f: (WSet) -> WSet): WExercise? {
            val s = sets.getOrNull(cmd.set) ?: return null
            return copy(sets = sets.mapIndexed { j, x -> if (j == cmd.set) f(s) else x })
        }
        return when (cmd.cmd) {
            WatchCommand.LOG_SET -> {
                val i = exerciseIndex(cmd) ?: return this
                val e = exercises[i]
                if (cmd.set !in e.sets.indices) return this
                edit { it.editSet { s -> s.copy(w = cmd.w, r = cmd.r, t = cmd.t, d = cmd.d, done = true) } }
                    .copy(rest = WRest(cmd.at + e.restSec * 1000L, e.restSec, e.name))
            }
            WatchCommand.UNDO_SET -> edit { it.editSet { s -> s.copy(done = false) } }
            WatchCommand.EFFORT -> edit { it.editSet { s -> s.copy(e = cmd.effort) } }
            WatchCommand.ADD_SET -> edit { it.copy(sets = it.sets + WSet(pw = it.sets.lastOrNull()?.pw ?: "")) }
            WatchCommand.REST_SKIP -> copy(rest = null)
            WatchCommand.REST_ADD -> rest?.let { copy(rest = it.copy(endsAt = it.endsAt + cmd.sec * 1000L, total = it.total + cmd.sec)) } ?: this
            WatchCommand.FINISH -> copy(active = false, finished = true, rest = null)
            else -> this
        }
    }

    /** The phone's snapshot plus the watch's commands it hasn't applied yet. */
    fun withPending(pending: List<WatchCommand>): WatchState =
        pending.filter { it.id !in acks }.fold(this) { s, c -> s.applying(c) }

    fun toJson(): String = buildJsonObject {
        put("v", WatchPaths.VERSION)
        put("active", active); put("id", id); put("type", type); put("title", title); put("startedAt", startedAt)
        put("exercises", JsonArray(exercises.map { it.toJson() }))
        put("rest", rest?.toJson() ?: JsonNull)
        put("acks", buildJsonArray { acks.forEach { add(JsonPrimitive(it)) } })
        put("finished", finished)
        put("sentAt", sentAt)
    }.toString()

    companion object {
        fun fromJson(text: String): WatchState? {
            val o = parse(text) ?: return null
            return WatchState(
                active = o.bool("active"), id = o.str("id"), type = o.str("type"), title = o.str("title"),
                startedAt = o.long("startedAt") ?: 0,
                exercises = (o["exercises"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(WExercise::fromJson) } ?: emptyList(),
                rest = (o["rest"] as? JsonObject)?.let(WRest::fromJson),
                acks = (o["acks"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList(),
                finished = o.bool("finished"),
                sentAt = o.long("sentAt") ?: 0,
            )
        }

        /** [[i]] or [[i, partner]] in plan order — WorkoutScreen's groupedExercises. */
        fun groups(exs: List<WExercise>): List<List<Int>> {
            val seen = HashSet<Int>()
            val out = ArrayList<List<Int>>()
            exs.forEachIndexed { i, ex ->
                if (i in seen) return@forEachIndexed
                val partner = if (ex.superset.isEmpty()) null else exs.indices.firstOrNull { it != i && exs[it].superset == ex.superset }
                if (partner != null && partner > i) { seen.add(i); seen.add(partner); out.add(listOf(i, partner)) }
                else { seen.add(i); out.add(listOf(i)) }
            }
            return out
        }

        /** "8-10" → "8" · "AMRAP" → "". */
        fun firstNumber(s: String): String = Regex("""\d+""").find(s)?.value ?: ""

        private fun key(s: String) = s.trim().lowercase()
    }
}

/** A watch workout's numbers, sent when it ends, so the phone can file it
 *  with the rest of the day's health data (Health Connect on Android; on
 *  Apple Watch, HealthKit saves the workout itself). */
data class WorkoutSummary(
    val start: Long,
    val end: Long,
    val type: String = "",
    val kcal: Double? = null,
    val avgHr: Double? = null,
    val maxHr: Double? = null,
    /** (epoch ms, bpm) */
    val hr: List<Pair<Long, Int>> = emptyList(),
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("start", start); put("end", end); put("type", type)
        kcal?.let { put("kcal", it) }; avgHr?.let { put("avgHr", it) }; maxHr?.let { put("maxHr", it) }
        put("hr", buildJsonArray { hr.forEach { (t, b) -> add(buildJsonArray { add(JsonPrimitive(t)); add(JsonPrimitive(b)) }) } })
    }

    companion object {
        fun fromJson(o: JsonObject): WorkoutSummary? {
            val start = o.long("start") ?: return null
            val end = o.long("end") ?: return null
            return WorkoutSummary(
                start, end, o.str("type"), o.double("kcal"), o.double("avgHr"), o.double("maxHr"),
                (o["hr"] as? JsonArray)?.mapNotNull { p ->
                    val a = p as? JsonArray ?: return@mapNotNull null
                    val t = (a.getOrNull(0) as? JsonPrimitive)?.longOrNull ?: return@mapNotNull null
                    val b = (a.getOrNull(1) as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null
                    t to b.toInt()
                } ?: emptyList(),
            )
        }
    }
}

data class WatchCommand(
    val id: String,
    /** When it happened on the wrist (epoch ms) — a set logged offline
     *  starts its rest from then, not from when the phone heard about it. */
    val at: Long,
    val cmd: String,
    val session: String = "",
    val ex: Int = -1,
    val name: String = "",
    val set: Int = -1,
    val w: String = "", val r: String = "", val t: String = "", val d: String = "",
    val effort: String = "",
    val sec: Int = 0,
    val rpe: Int = 0,
    val workout: WorkoutSummary? = null,
) {
    fun toJson(): String = buildJsonObject {
        put("v", WatchPaths.VERSION)
        put("id", id); put("at", at); put("cmd", cmd); put("session", session)
        put("ex", ex); put("name", name); put("set", set)
        put("w", w); put("r", r); put("t", t); put("d", d)
        put("effort", effort); put("sec", sec); put("rpe", rpe)
        workout?.let { put("workout", it.toJson()) }
    }.toString()

    companion object {
        const val LOG_SET = "logSet"
        const val UNDO_SET = "undoSet"
        const val EFFORT = "effort"
        const val ADD_SET = "addSet"
        const val REST_SKIP = "restSkip"
        const val REST_ADD = "restAdd"
        const val FINISH = "finish"
        /** "Send me the current state" — the watch app just opened. */
        const val SYNC = "sync"
        const val WORKOUT = "workout"

        fun fromJson(text: String): WatchCommand? {
            val o = parse(text) ?: return null
            val id = o.str("id").ifEmpty { return null }
            val cmd = o.str("cmd").ifEmpty { return null }
            return WatchCommand(
                id = id, at = o.long("at") ?: 0, cmd = cmd, session = o.str("session"),
                ex = o.long("ex")?.toInt() ?: -1, name = o.str("name"), set = o.long("set")?.toInt() ?: -1,
                w = o.str("w"), r = o.str("r"), t = o.str("t"), d = o.str("d"),
                effort = o.str("effort"), sec = o.long("sec")?.toInt() ?: 0, rpe = o.long("rpe")?.toInt() ?: 0,
                workout = (o["workout"] as? JsonObject)?.let(WorkoutSummary::fromJson),
            )
        }
    }
}

// ── lenient JSON reads (a field of the wrong type reads as missing) ──

private fun parse(text: String): JsonObject? = try { Json.parseToJsonElement(text) as? JsonObject } catch (_: Exception) { null }

private fun JsonObject.prim(k: String): JsonPrimitive? = this[k] as? JsonPrimitive

private fun JsonObject.str(k: String): String = prim(k)?.takeIf { it.isString }?.content
    ?: prim(k)?.takeIf { it !is JsonNull && !it.isString }?.content ?: ""

private fun JsonObject.bool(k: String): Boolean = prim(k)?.booleanOrNull ?: false

private fun JsonObject.long(k: String): Long? = prim(k)?.let { it.longOrNull ?: it.doubleOrNull?.toLong() }

private fun JsonObject.double(k: String): Double? = prim(k)?.doubleOrNull
