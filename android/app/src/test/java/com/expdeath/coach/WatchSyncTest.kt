package com.expdeath.coach

import com.expdeath.coach.app.RestTimer
import com.expdeath.coach.app.WatchSync
import com.expdeath.coach.models.FinishInfo
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.watchlink.WRest
import com.expdeath.coach.watchlink.WatchCommand
import com.expdeath.coach.watchlink.WorkoutSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The phone half of the watch app: what it shows the watch, and that a
 *  command from the wrist becomes the same edit a tap on the phone makes. */
class WatchSyncTest {
    private class Fake(
        override var todayPlan: Session?,
        override var history: List<Session> = emptyList(),
        override var rest: RestTimer? = null,
    ) : WatchSync.Target {
        val calls = mutableListOf<String>()
        override fun updateSet(exI: Int, setI: Int, weight: String?, reps: String?, time: String?, dist: String?, done: Boolean?, effort: String?) {
            calls.add("set $exI/$setI w=$weight r=$reps t=$time d=$dist done=$done e=$effort")
        }
        override fun addSet(exI: Int) { calls.add("addSet $exI") }
        override fun startRest(seconds: Double, exName: String, startedAt: Long) { calls.add("rest ${seconds.toInt()} $exName @$startedAt") }
        override fun extendRest(seconds: Int) { calls.add("extend $seconds") }
        override fun stopRest() { calls.add("stopRest") }
        override fun finish(rpe: Int) { calls.add("finish $rpe") }
        override fun saveWorkout(w: WorkoutSummary, title: String) { calls.add("save $title") }
    }

    private val plan = Plan(
        sessionType = "Push", title = "Push — strength",
        exercises = listOf(
            Plan.Exercise("Bench Press", sets = 3, reps = "6-8", rest = "2min", suggestedWeight = "60kg"),
            Plan.Exercise("Plank", sets = 2, reps = "45s", rest = "45s"),
        ),
    )
    private val today = Session(
        id = "2026-10-10#1000", date = "2026-10-10", startedAt = 1000.0, checkin = null, plan = plan,
        log = listOf(listOf(SetLog("60", "8", done = true, effort = "good"), SetLog(), SetLog()), listOf(SetLog(), SetLog())),
    )
    // last time: every set at the top of 6-8 → +2.5 kg today
    private val lastWeek = Session(
        id = "2026-10-03#1", date = "2026-10-03", startedAt = 1.0, checkin = null, finished = true,
        plan = Plan(sessionType = "Push", exercises = listOf(Plan.Exercise("Bench Press", sets = 2, reps = "6-8"))),
        log = listOf(listOf(SetLog("60", "8", done = true), SetLog("60", "8", done = true))),
    )

    private fun cmd(c: String, ex: Int = 0, name: String = "Bench Press", set: Int = 1, id: String = c, session: String = today.id) =
        WatchCommand(id = id, at = 5_000, cmd = c, session = session, ex = ex, name = name, set = set)

    @Before fun setUp() {
        Cloud.offline = true
        LocalStore.wipe()
        WatchSync.reset()
    }

    @Test fun snapshotShowsTodaysWorkoutWithThePhonesHints() {
        val s = WatchSync.snapshot(Fake(today, listOf(lastWeek), RestTimer(9_000, 120.0, "Bench Press")), now = 7)
        assertTrue(s.active)
        assertEquals(today.id, s.id)
        assertEquals(1000L, s.startedAt)
        val bench = s.exercises[0]
        assertEquals(Stats.logMode("Bench Press", "Push"), bench.mode)
        assertEquals(120, bench.restSec)
        assertEquals("62.5", bench.target)
        assertEquals("60kg×8, 60kg×8", bench.last)
        assertEquals(listOf(true, false, false), bench.sets.map { it.done })
        assertEquals("good", bench.sets[0].e)
        assertEquals("62.5", bench.sets[1].pw)
        assertEquals("8", bench.sets[1].pr)
        assertEquals("check", s.exercises[1].mode) // planks get ticked, not weighed
        assertEquals(WRest(9_000, 120, "Bench Press"), s.rest)
        assertEquals(1 to 5, s.doneSets to s.totalSets)
    }

    @Test fun noWorkoutAndFinishedWorkoutSnapshots() {
        assertFalse(WatchSync.snapshot(Fake(null)).active)
        val done = WatchSync.snapshot(Fake(today.copy(finished = true, fin = FinishInfo())))
        assertFalse(done.active)
        assertTrue(done.finished)
    }

    @Test fun aSetLoggedOnTheWatchIsSavedAndStartsRestFromTheWrist() {
        val app = Fake(today)
        WatchSync.handle(app, cmd(WatchCommand.LOG_SET).copy(w = "62.5", r = "7"), now = 6_000)
        assertEquals(listOf(
            "set 0/1 w=62.5 r=7 t=null d=null done=true e=null",
            "rest 120 Bench Press @5000",
        ), app.calls)
        assertEquals(6_000L, WatchSync.lastContact) // the watch counts as in use
    }

    @Test fun eachCommandIsAppliedOnceAndAcked() {
        val app = Fake(today)
        WatchSync.handle(app, cmd(WatchCommand.EFFORT, id = "c1").copy(effort = "easy"))
        WatchSync.handle(app, cmd(WatchCommand.EFFORT, id = "c1").copy(effort = "easy")) // redelivered
        assertEquals(1, app.calls.size)
        assertTrue("c1" in WatchSync.snapshot(app).acks)
    }

    @Test fun commandsForAnOldSessionAreIgnored() {
        val app = Fake(today)
        WatchSync.handle(app, cmd(WatchCommand.LOG_SET, session = "2026-10-09#5"))
        WatchSync.handle(app, cmd(WatchCommand.REST_SKIP, id = "x", session = "2026-10-09#5"))
        assertTrue(app.calls.isEmpty())
    }

    @Test fun theExerciseIsFoundByNameAfterThePlanChanged() {
        // Bench was removed on the phone; the watch still thinks Plank is #1
        val app = Fake(today.copy(plan = plan.copy(exercises = listOf(plan.exercises[1])), log = listOf(today.log[1])))
        WatchSync.handle(app, cmd(WatchCommand.LOG_SET, ex = 1, name = "Plank", set = 0))
        assertEquals("set 0/0 w=null r=null t=null d=null done=true e=null", app.calls.first())
    }

    @Test fun badEffortsAreRefusedAndRpeIsClamped() {
        val app = Fake(today)
        WatchSync.handle(app, cmd(WatchCommand.EFFORT, id = "e").copy(effort = "<script>"))
        WatchSync.handle(app, cmd(WatchCommand.FINISH, id = "f").copy(rpe = 42))
        assertEquals(listOf("finish 7"), app.calls)
    }

    @Test fun restAndSetEditsMapToTheSameAppStateCalls() {
        val app = Fake(today)
        WatchSync.handle(app, cmd(WatchCommand.REST_ADD, id = "1").copy(sec = 15))
        WatchSync.handle(app, cmd(WatchCommand.REST_SKIP, id = "2"))
        WatchSync.handle(app, cmd(WatchCommand.ADD_SET, id = "3"))
        WatchSync.handle(app, cmd(WatchCommand.UNDO_SET, id = "4", set = 0))
        assertEquals(listOf("extend 15", "stopRest", "addSet 0", "set 0/0 w=null r=null t=null d=null done=false e=null"), app.calls)
    }

    @Test fun aWatchWorkoutIsFiledEvenAfterTheSessionEnded() {
        val app = Fake(today.copy(finished = true))
        WatchSync.handle(app, WatchCommand("w", 1, WatchCommand.WORKOUT, workout = WorkoutSummary(1, 2)))
        assertEquals(listOf("save Push — strength"), app.calls)
    }
}
