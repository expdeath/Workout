package com.expdeath.coach.app

import com.expdeath.coach.models.FinishInfo
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.parseDouble
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.sync.HealthConnectSync
import com.expdeath.coach.ui.screens.parseRestSeconds
import com.expdeath.coach.watchlink.WExercise
import com.expdeath.coach.watchlink.WRest
import com.expdeath.coach.watchlink.WSet
import com.expdeath.coach.watchlink.WatchCommand
import com.expdeath.coach.watchlink.WatchState
import com.expdeath.coach.watchlink.WorkoutSummary
import kotlinx.coroutines.launch

/** The phone half of the watch app (docs/watch.md): turns today's session
 *  into the [WatchState] the watch shows, and applies the watch's commands
 *  through the same AppState edits the Workout screen makes — so a set
 *  logged on the wrist is saved, synced and backed up exactly like one
 *  typed on the phone. Transport-free: WearBridge (Wear OS Data Layer)
 *  plugs into [sender] / [opener]. */
object WatchSync {
    /** Delivers a state snapshot to the watch. Null in unit tests. */
    var sender: ((String) -> Unit)? = null
    /** Opens COACH on the watch (a workout just started). */
    var opener: (() -> Unit)? = null

    /** When the watch last sent anything (ms). While it's recent the phone
     *  keeps its rest-over notification off the watch — the watch app buzzes. */
    @Volatile var lastContact = 0L
    val watchActive: Boolean get() = System.currentTimeMillis() - lastContact < 30 * 60_000L

    private val applied = ArrayDeque<String>()
    private var lastSent: String? = null

    internal fun reset() { applied.clear(); lastSent = null; lastContact = 0 }

    private val efforts = setOf("", "easy", "good", "grind")

    /** What a running workout needs from the app — AppState, or a fake in tests. */
    interface Target {
        val todayPlan: Session?
        val history: List<Session>
        val rest: RestTimer?
        fun updateSet(exI: Int, setI: Int, weight: String? = null, reps: String? = null, time: String? = null, dist: String? = null, done: Boolean? = null, effort: String? = null)
        fun addSet(exI: Int)
        fun startRest(seconds: Double, exName: String, startedAt: Long)
        fun extendRest(seconds: Int)
        fun stopRest()
        fun finish(rpe: Int)
        fun saveWorkout(w: WorkoutSummary, title: String)
    }

    private class AppTarget(val app: AppState) : Target {
        override val todayPlan get() = app.todayPlan
        override val history get() = app.history
        override val rest get() = app.rest
        override fun updateSet(exI: Int, setI: Int, weight: String?, reps: String?, time: String?, dist: String?, done: Boolean?, effort: String?) {
            app.updateSet(exI, setI, weight, reps, time, dist, done, effort)
        }
        override fun addSet(exI: Int) = app.adjustSets(exI, 1)
        override fun startRest(seconds: Double, exName: String, startedAt: Long) = app.startRest(seconds, exName, startedAt, fromWatch = true)
        override fun extendRest(seconds: Int) = app.extendRest(seconds)
        override fun stopRest() = app.stopRest()
        override fun finish(rpe: Int) {
            app.fin = FinishInfo(rpe = rpe)
            app.finishSession()
        }
        override fun saveWorkout(w: WorkoutSummary, title: String) {
            app.scope.launch { HealthConnectSync.saveWatchWorkout(w, title) }
        }
    }

    fun snapshot(app: Target, now: Long = System.currentTimeMillis()): WatchState {
        val acks = applied.toList()
        val t = app.todayPlan
        if (t == null || t.plan.exercises.isEmpty()) return WatchState(acks = acks, sentAt = now)
        if (t.finished) return WatchState(id = t.id, type = t.plan.sessionType, title = t.plan.title, finished = true, acks = acks, sentAt = now)
        val exercises = t.plan.exercises.mapIndexed { i, ex ->
            // the same hints WorkoutScreen's ExHeader / SetRow show
            val mode = Stats.logMode(ex.name, t.plan.sessionType)
            val lastPerf = Stats.lastPerformance(app.history, ex.name)
            val suggest = if (mode != "strength") null else Stats.suggestNextWeight(lastPerf, ex.reps)
            val leading = Stats.firstMatch("""^\s*(\d+(?:\.\d+)?)""", ex.suggestedWeight)?.getOrNull(1)?.let { parseDouble(it) }
            WExercise(
                name = ex.name, mode = mode, reps = ex.reps, rpe = ex.rpe,
                restSec = parseRestSeconds(ex.rest).toInt(),
                target = if (mode == "strength") (suggest ?: leading)?.let { Helpers.fmtKg(it) } ?: "" else "",
                last = lastPerf?.sets?.joinToString(", ") { it.formatted } ?: "",
                superset = ex.superset,
                sets = (t.log.getOrNull(i) ?: emptyList()).mapIndexed { j, s ->
                    val last = lastPerf?.sets?.getOrNull(j)
                    WSet(
                        w = s.weight, r = s.reps, t = s.time, d = s.dist, done = s.done, e = s.effort,
                        pw = suggest?.let { Helpers.fmtKg(it) } ?: last?.weight ?: "",
                        pr = last?.reps ?: "", pt = last?.time ?: "",
                    )
                },
            )
        }
        return WatchState(
            active = true, id = t.id, type = t.plan.sessionType, title = t.plan.title, startedAt = t.startedAt.toLong(),
            exercises = exercises, rest = app.rest?.let { WRest(it.endsAt, it.total.toInt(), it.exName) },
            acks = acks, sentAt = now,
        )
    }

    /** Sends the current state when it changed (or always, with `force` —
     *  the watch asked, or just applied a command). */
    fun publish(app: AppState, force: Boolean = false) = publish(AppTarget(app), force)

    private fun publish(app: Target, force: Boolean) {
        val send = sender ?: return
        val s = snapshot(app)
        val key = s.copy(sentAt = 0).toJson()
        if (!force && key == lastSent) return
        lastSent = key
        send(s.toJson())
    }

    fun workoutStarted() { opener?.invoke() }

    /** Applies one command from the watch. Main thread, like every AppState edit. */
    fun handle(app: AppState, cmd: WatchCommand) = handle(AppTarget(app), cmd)

    fun handle(app: Target, cmd: WatchCommand, now: Long = System.currentTimeMillis()) {
        lastContact = now
        if (cmd.id in applied) { publish(app, force = true); return } // a redelivery
        applied.addLast(cmd.id)
        while (applied.size > 40) applied.removeFirst()

        val t = app.todayPlan
        val live = t != null && !t.finished && (cmd.session.isEmpty() || cmd.session == t.id)
        val snap = snapshot(app, now)
        val i = snap.exerciseIndex(cmd)
        when (cmd.cmd) {
            WatchCommand.SYNC -> {}
            WatchCommand.WORKOUT -> cmd.workout?.let { w ->
                app.saveWorkout(w, t?.plan?.title?.ifEmpty { null } ?: t?.plan?.sessionType ?: "COACH workout")
            }
            WatchCommand.LOG_SET -> if (live && i != null) {
                val ex = snap.exercises[i]
                when (ex.mode) {
                    "strength" -> app.updateSet(i, cmd.set, weight = cmd.w, reps = cmd.r, done = true)
                    "cardio" -> app.updateSet(i, cmd.set, time = cmd.t, dist = cmd.d, done = true)
                    else -> app.updateSet(i, cmd.set, done = true)
                }
                LocalStore.logEvent("watch_set_logged", mapOf("exercise" to JSONValue.Str(ex.name)))
                // rest runs from when the set was logged on the wrist
                app.startRest(ex.restSec.toDouble(), ex.name, startedAt = minOf(cmd.at.takeIf { it > 0 } ?: now, now))
            }
            WatchCommand.UNDO_SET -> if (live && i != null) app.updateSet(i, cmd.set, done = false)
            WatchCommand.EFFORT -> if (live && i != null && cmd.effort in efforts) app.updateSet(i, cmd.set, effort = cmd.effort)
            WatchCommand.ADD_SET -> if (live && i != null) app.addSet(i)
            WatchCommand.REST_SKIP -> if (live) app.stopRest()
            WatchCommand.REST_ADD -> if (live) app.extendRest(cmd.sec.coerceIn(5, 300))
            WatchCommand.FINISH -> if (live) {
                LocalStore.logEvent("watch_finished")
                app.finish(if (cmd.rpe in 1..10) cmd.rpe else 7)
            }
        }
        publish(app, force = true)
    }
}
