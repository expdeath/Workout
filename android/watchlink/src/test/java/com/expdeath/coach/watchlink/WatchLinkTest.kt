package com.expdeath.coach.watchlink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The protocol both watches speak (docs/watch.md). WatchLinkTests.swift
 *  on the ios branch pins the same behaviour for the Apple Watch. */
class WatchLinkTest {
    private fun ex(name: String, n: Int = 3, superset: String = "", rest: Int = 90, done: Int = 0) =
        WExercise(name, restSec = rest, superset = superset, sets = List(n) { WSet(done = it < done) })

    private fun cmd(c: String, ex: Int = -1, name: String = "", set: Int = -1, id: String = c, session: String = "s1", at: Long = 1_000) =
        WatchCommand(id = id, at = at, cmd = c, session = session, ex = ex, name = name, set = set)

    @Test fun stateRoundTripsThroughJson() {
        val s = WatchState(
            active = true, id = "2026-10-10#1", type = "Push", title = "Push — strength", startedAt = 42,
            exercises = listOf(WExercise("Bench", "strength", "6-8", "8", 120, "62.5", "60kg×8", "A",
                listOf(WSet("60", "8", done = true, e = "good", pw = "62.5", pr = "8")))),
            rest = WRest(99, 120, "Bench"), acks = listOf("a", "b"), sentAt = 7,
        )
        assertEquals(s, WatchState.fromJson(s.toJson()))
    }

    @Test fun commandRoundTripsThroughJson() {
        val c = WatchCommand("id1", 5, WatchCommand.LOG_SET, "s1", 2, "Bench", 1, "60", "8", effort = "easy", sec = 15, rpe = 8,
            workout = WorkoutSummary(1, 2, "Push", 210.5, 128.0, 171.0, listOf(10L to 120, 20L to 130)))
        assertEquals(c, WatchCommand.fromJson(c.toJson()))
    }

    /** What the Apple Watch writes (sorted keys, Swift's JSONSerialization) reads the same here. */
    @Test fun readsTheSwiftEncoding() {
        val swift = """{"acks":["c1"],"active":true,"exercises":[{"last":"","mode":"strength","name":"Bench","reps":"6-8","restSec":120,"rpe":"","sets":[{"d":"","done":true,"e":"good","pr":"","pt":"","pw":"","r":"8","t":"","w":"60"}],"superset":"","target":"62.5"}],"finished":false,"id":"s1","rest":null,"sentAt":5,"startedAt":1000,"title":"T","type":"Push","v":1}"""
        val s = WatchState.fromJson(swift)!!
        assertEquals(WSet("60", "8", done = true, e = "good"), s.exercises[0].sets[0])
        assertNull(s.rest)
        assertEquals(listOf("c1"), s.acks)
        val c = WatchCommand.fromJson("""{"at":5,"cmd":"logSet","d":"","effort":"","ex":0,"id":"x","name":"Bench","r":"8","rpe":0,"sec":0,"session":"s1","set":1,"t":"","v":1,"w":"60"}""")!!
        assertEquals(WatchCommand("x", 5, WatchCommand.LOG_SET, "s1", 0, "Bench", 1, "60", "8"), c)
    }

    @Test fun badJsonIsIgnoredNotFatal() {
        assertNull(WatchState.fromJson("not json"))
        assertNull(WatchCommand.fromJson("""{"cmd":"logSet"}""")) // no id
        // wrong types read as missing
        val s = WatchState.fromJson("""{"active":"yes","exercises":[{"name":"Row","restSec":"x","sets":[{"done":1}]}]}""")!!
        assertFalse(s.active)
        assertEquals(90, s.exercises[0].restSec)
        assertFalse(s.exercises[0].sets[0].done)
    }

    @Test fun nextFollowsPlanOrder() {
        val s = WatchState(exercises = listOf(ex("A", 2, done = 2), ex("B", 3, done = 1), ex("C")))
        assertEquals(WFocus(1, 1), s.next())
        assertNull(WatchState(exercises = listOf(ex("A", 2, done = 2))).next())
    }

    @Test fun supersetsAlternateRounds() {
        // A1 B1 A2 B2 — like the phone's superset card
        var s = WatchState(id = "s1", exercises = listOf(ex("A", 2, "x"), ex("B", 2, "x"), ex("C", 1)))
        val order = mutableListOf<WFocus>()
        while (true) {
            val f = s.next() ?: break
            order.add(f)
            s = s.applying(cmd(WatchCommand.LOG_SET, f.ex, s.exercises[f.ex].name, f.set, id = "${f.ex}${f.set}"))
        }
        assertEquals(listOf(WFocus(0, 0), WFocus(1, 0), WFocus(0, 1), WFocus(1, 1), WFocus(2, 0)), order)
    }

    @Test fun prefillUsesWhatYouJustLiftedThenTheHint() {
        val e = WExercise("Bench", reps = "6-8", target = "62.5", sets = listOf(
            WSet("60", "8", done = true, pw = "62.5", pr = "8"), WSet(pw = "62.5", pr = "7"),
        ))
        val s = WatchState(exercises = listOf(e, WExercise("Row", reps = "10-12", target = "40", sets = listOf(WSet()))))
        assertEquals(WPrefill("60", "8", "", ""), s.prefill(0, 1))
        assertEquals(WPrefill("40", "10", "", ""), s.prefill(1, 0)) // nothing logged: target, bottom of the range
    }

    @Test fun loggingASetOnTheWristStartsRestFromThen() {
        val s = WatchState(id = "s1", exercises = listOf(ex("Bench", rest = 120)))
            .applying(cmd(WatchCommand.LOG_SET, 0, "Bench", 0, at = 10_000).copy(w = "60", r = "8"))
        assertEquals(WSet("60", "8", done = true), s.exercises[0].sets[0])
        assertEquals(WRest(130_000, 120, "Bench"), s.rest)
        val more = s.applying(cmd(WatchCommand.REST_ADD, id = "x").copy(sec = 15))
        assertEquals(WRest(145_000, 135, "Bench"), more.rest)
        assertNull(more.applying(cmd(WatchCommand.REST_SKIP, id = "y")).rest)
    }

    @Test fun commandsForAnotherSessionDoNothing() {
        val s = WatchState(id = "today", exercises = listOf(ex("Bench")))
        assertEquals(s, s.applying(cmd(WatchCommand.LOG_SET, 0, "Bench", 0, session = "yesterday")))
    }

    @Test fun exerciseIsFoundByNameWhenThePlanChanged() {
        // the phone removed exercise 0 after the watch logged against it
        val s = WatchState(id = "s1", exercises = listOf(ex("Row"), ex("Bench")))
        val c = cmd(WatchCommand.LOG_SET, 0, "Bench", 0)
        assertEquals(1, s.exerciseIndex(c))
        assertTrue(s.applying(c).exercises[1].sets[0].done)
        assertNull(s.exerciseIndex(cmd(WatchCommand.LOG_SET, 0, "Squat", 0)))
    }

    @Test fun pendingCommandsDropOnceThePhoneAcksThem() {
        val phone = WatchState(id = "s1", exercises = listOf(ex("Bench")))
        val c = cmd(WatchCommand.LOG_SET, 0, "Bench", 0, id = "c1")
        assertTrue(phone.withPending(listOf(c)).exercises[0].sets[0].done)
        // the phone's answer already has it (and says so) — not applied twice
        val answered = phone.copy(exercises = listOf(ex("Bench", done = 1)), acks = listOf("c1"))
        assertEquals(answered, answered.withPending(listOf(c)))
    }

    @Test fun finishEndsTheWorkoutOnTheWatch() {
        val s = WatchState(active = true, id = "s1", exercises = listOf(ex("Bench")), rest = WRest(1, 1, "Bench"))
            .applying(cmd(WatchCommand.FINISH).copy(rpe = 8))
        assertFalse(s.active); assertTrue(s.finished); assertNull(s.rest)
    }
}
