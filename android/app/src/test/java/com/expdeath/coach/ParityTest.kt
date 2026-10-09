package com.expdeath.coach

import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.SavedWorkout
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.HealthIngest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Behaviour the web app has that the native apps must match
 *  (src/utils/healthIngest.js, src/utils/workouts.js). */
class ParityTest {
    @Before fun setUp() {
        Cloud.offline = true
        LocalStore.wipe()
    }

    @Test fun pastedHealthTextFillsTodaysNumbers() {
        HealthIngest.storeToday("  HRV: 48 RHR: 57 SleepHrs: 7.5 Steps: 8,432  ")
        val row = LocalStore.backup.health.first { it.date == Helpers.todayStr() }
        assertEquals(48.0, row.hrv!!, 0.0); assertEquals(57.0, row.rhr!!, 0.0)
        assertEquals(7.5, row.sleepH!!, 0.0); assertEquals(8432.0, row.steps!!, 0.0)
        assertEquals("HRV: 48 RHR: 57 SleepHrs: 7.5 Steps: 8,432", HealthIngest.todaysText())
    }

    @Test fun textWithoutNumbersPrefillsButWritesNoRow() {
        HealthIngest.storeToday("felt great, slept well")
        assertTrue(LocalStore.backup.health.isEmpty())
        assertEquals("felt great, slept well", HealthIngest.todaysText())
    }

    @Test fun clipboardHeuristicMatchesTheWeb() {
        assertTrue(HealthIngest.looksLikeHealthData("HRV 52 · RHR 57 · Steps 8400"))
        assertFalse(HealthIngest.looksLikeHealthData("buy milk"))
        assertFalse(HealthIngest.looksLikeHealthData("sleep well"))
        assertFalse(HealthIngest.looksLikeHealthData("HRV 5".repeat(200)))
    }

    @Test fun reparseFillsMissingFieldsAndRepairsDoubledSleep() {
        LocalStore.mergeHealth(HealthRow("2026-09-01", raw = "HRV: 50 RHR: 60"))
        LocalStore.mergeHealth(HealthRow("2026-09-02", sleepH = 15.0, raw = "SleepHrs: 54000"))
        HealthIngest.reparseRows()
        val h = LocalStore.backup.health.associateBy { it.date }
        assertEquals(50.0, h["2026-09-01"]!!.hrv!!, 0.0); assertEquals(60.0, h["2026-09-01"]!!.rhr!!, 0.0)
        assertEquals("doubled sleep repaired", 7.5, h["2026-09-02"]!!.sleepH!!, 0.0)
    }

    @Test fun savedWorkoutPlansRecordWhereTheyCameFrom() {
        val w = SavedWorkout(id = "w1", name = "Upper A", source = "trainer", trainer = "Sam", adapt = true,
            exercises = listOf(SavedWorkout.Exercise("Bench Press", 2, "6")))
        val p = Workouts.templateToPlan(w, emptyList())
        assertEquals(JSONValue.obj("id" to JSONValue.Str("w1"), "name" to JSONValue.Str("Upper A"), "source" to JSONValue.Str("trainer"),
            "trainer" to JSONValue.Str("Sam"), "adapt" to JSONValue.Bool(true)), p.fromWorkout)
        assertEquals("2 sets × 2.5 min, like the web (no 30-min floor)", 5, p.estTimeMin)
        val exact = Workouts.enforceExact(Plan(sessionType = "Push"), w, emptyList())
        assertEquals(JSONValue.Bool(false), exact.fromWorkout!!.obj!!["adapt"])
        // and it round-trips through the stored session JSON
        assertEquals(p.fromWorkout, Plan.fromJson(p.toJson())!!.fromWorkout)
        assertNull(Plan.fromJson(Plan(sessionType = "Push").toJson())!!.fromWorkout)
    }

    @Test fun emptyWorkoutStillEstimatesThirtyMinutes() =
        assertEquals(30, Workouts.templateToPlan(SavedWorkout(name = "Empty"), emptyList()).estTimeMin)
}
