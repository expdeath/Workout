package com.expdeath.coach

import com.expdeath.coach.models.AISettings
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.DeletedId
import com.expdeath.coach.models.Event
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.persistence.LocalStore
import com.expdeath.coach.stats.Dashboard
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.Stats
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.GitHubSync
import com.expdeath.coach.sync.HealthConnectSync
import com.expdeath.coach.ui.screens.parseRestSeconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Port of StatsTests.swift — the regex health parser and the progression
 *  logic, against real Watch-shortcut-shaped payloads. */
class StatsTest {
    @Test fun shortcutLabelFormat() {
        val n = Stats.parseHealthNumbers("HRV: 48.2 RHR: 57 SleepHrs: 7.5 Steps: 8,432")
        assertEquals(48.2, n.hrv!!, 0.0); assertEquals(57.0, n.rhr!!, 0.0); assertEquals(7.5, n.sleepH!!, 0.0); assertEquals(8432.0, n.steps!!, 0.0)
    }

    @Test fun sleepHrsInSecondsDedupesDoubleCount() = assertEquals(7.5, Stats.parseHealthNumbers("SleepHrs: 54000").sleepH!!, 0.0)

    @Test fun freeformSleepFallback() = assertEquals(6.5, Stats.parseHealthNumbers("slept 6.5 hours last night, felt okay").sleepH!!, 0.0)

    @Test fun freeformSleepColonFormatRoundsToOneDecimal() = assertEquals(7.3, Stats.parseHealthNumbers("sleep: 7:20").sleepH!!, 0.0)

    @Test fun spo2FractionVsPercent() {
        assertEquals(96.0, Stats.parseHealthNumbers("SpO2: 0.96").spo2!!, 0.0)
        assertEquals(96.0, Stats.parseHealthNumbers("SpO2: 96").spo2!!, 0.0)
    }

    @Test fun vo2maxOutOfRangeIsDropped() = assertNull(Stats.parseHealthNumbers("VO2Max: 200").vo2max)

    @Test fun emptyStringReturnsAllNull() {
        val n = Stats.parseHealthNumbers("")
        assertNull(n.hrv); assertNull(n.rhr); assertNull(n.sleepH)
    }

    private fun lp(vararg sets: SetLog) = Stats.LastPerformance("2026-01-01", sets.toList(), "10-12")

    @Test fun allSetsToppedOutSuggestsPlus2point5() =
        assertEquals(62.5, Stats.suggestNextWeight(lp(SetLog("60", "12", true), SetLog("60", "12", true)), "10-12")!!, 0.0)

    @Test fun allSetsEasySuggestsPlus5() =
        assertEquals(65.0, Stats.suggestNextWeight(lp(SetLog("60", "12", true, effort = "easy"), SetLog("60", "12", true, effort = "easy")), "10-12")!!, 0.0)

    @Test fun anyGrindHoldsWeight() =
        assertNull(Stats.suggestNextWeight(lp(SetLog("60", "12", true, effort = "grind"), SetLog("60", "12", true)), "10-12"))

    @Test fun notAllToppedOutHoldsWeight() = assertNull(Stats.suggestNextWeight(lp(SetLog("60", "9", true)), "10-12"))

    @Test fun muscleGroups() {
        assertEquals("Legs", Stats.muscleGroupOf("Leg Press"))
        assertEquals("Core", Stats.muscleGroupOf("Hanging Leg Raise"))
        assertEquals("Cardio", Stats.muscleGroupOf("Hike"))
        assertEquals("Other", Stats.muscleGroupOf("Juggling"))
    }

    @Test fun epley() {
        assertEquals(100.0, Stats.epley1RM("100", "1")!!, 0.0)
        assertNull(Stats.epley1RM("", "8")); assertNull(Stats.epley1RM("60", "")); assertNull(Stats.epley1RM("0", "8"))
    }

    private fun bench(id: String, date: String, w: String) = Session(id, date, 0.0, null,
        Plan(sessionType = "Push", exercises = listOf(Plan.Exercise(name = "Bench Press", sets = 3, reps = "8-10")), estTimeMin = 45),
        listOf(listOf(SetLog(w, "8", true))), true)

    @Test fun newWeightBeatsOldRecord() {
        val prs = Stats.detectPRs(bench("t1", "2026-01-08", "65"), listOf(bench("p1", "2026-01-01", "60")))
        assertEquals(1, prs.size); assertEquals("weight", prs[0].kind); assertEquals(60.0, prs[0].from, 0.0); assertEquals(65.0, prs[0].to, 0.0)
    }

    @Test fun firstTimeExerciseIsNotAPR() = assertTrue(Stats.detectPRs(bench("t1", "2026-01-08", "65"), emptyList()).isEmpty())
}

/** Port of HelpersTests.swift — quickReadiness, dates, plate math, rest parsing. */
class HelpersTest {
    @Test fun quickReadiness() {
        assertEquals(75, Helpers.quickReadiness(Checkin()))
        assertEquals(5, Helpers.quickReadiness(Checkin(energy = 3, sleep = "Poor", soreness = "Very sore", backTight = true)))
        assertEquals(98, Helpers.quickReadiness(Checkin(energy = 10, sleep = "Great", soreness = "None")))
    }

    @Test fun daysAgoStr() {
        assertEquals(Helpers.todayStr(), Helpers.daysAgoStr(0))
        assertEquals(LocalDate.parse(Helpers.todayStr()).minusDays(1).toString(), Helpers.daysAgoStr(1))
    }

    @Test fun plateBreakdownGreedyPerSide() {
        val b = Helpers.plateBreakdown(25.0)!!
        assertEquals(listOf(2.5), b.perSide); assertTrue(b.exact)
        val c = Helpers.plateBreakdown(101.0, 20.0, listOf(20.0, 10.0, 5.0, 2.5))!!
        assertEquals(listOf(20.0, 20.0), c.perSide); assertEquals(100.0, c.loaded, 0.0); assertFalse(c.exact)
        assertEquals("lighter than the bar → bar only", emptyList<Double>(), Helpers.plateBreakdown(15.0)!!.perSide)
        assertNull(Helpers.plateBreakdown(0.0))
    }

    @Test fun parsePlatesDedupesAndSorts() {
        assertEquals(listOf(25.0, 20.0, 2.5), Helpers.parsePlates("2.5, 25 20,20  60"))
        assertNull(Helpers.parsePlates("none"))
    }

    @Test fun restSeconds() {
        assertEquals(90.0, parseRestSeconds("90s"), 0.0)
        assertEquals(120.0, parseRestSeconds("2min"), 0.0)
        assertEquals(120.0, parseRestSeconds("1-2min"), 0.0)
        assertEquals(90.0, parseRestSeconds(""), 0.0)
        assertEquals("clamped to ≥15s", 15.0, parseRestSeconds("5s"), 0.0)
    }

    @Test fun setInputClamping() {
        assertEquals("200", Helpers.cleanWeight("1000"))
        assertEquals("62.5", Helpers.cleanWeight("62.5"))
        assertEquals("62.", Helpers.cleanWeight("62."))
        assertEquals("1.25", Helpers.cleanWeight("1.2.5"))
        assertEquals("30", Helpers.cleanReps("99"))
        assertEquals("", Helpers.cleanReps("x"))
    }
}

/** Port of GitHubSyncTests.swift — the merge rules of src/db/sync.js. */
class GitHubSyncTest {
    private fun session(id: String, date: String, updatedAt: Double, finished: Boolean = true, deleted: Boolean = false) =
        Session(id, date, 0.0, null, Plan(), emptyList(), finished, updatedAt = updatedAt, deleted = deleted)

    @Test fun foldsInPlaceTombstoneIntoDeletedIds() {
        val out = GitHubSync.normalizeBackup(Backup(sessions = listOf(session("2026-01-01#1", "2026-01-01", 100.0, deleted = true))))
        assertTrue(out.sessions.isEmpty()); assertEquals(listOf("2026-01-01#1"), out.deletedIds.map { it.id })
    }

    @Test fun filtersSessionsAlreadyInDeletedIds() =
        assertTrue(GitHubSync.normalizeBackup(Backup(deletedIds = listOf(DeletedId("s1", 50.0)), sessions = listOf(session("s1", "2026-01-01", 100.0)))).sessions.isEmpty())

    @Test fun dropsSessionsWithNoDate() = assertTrue(GitHubSync.normalizeBackup(Backup(sessions = listOf(session("s1", "", 100.0)))).sessions.isEmpty())

    @Test fun newerUpdatedAtWins() {
        val m = GitHubSync.mergeBackups(Backup(sessions = listOf(session("s1", "2026-01-01", 100.0, false))), Backup(sessions = listOf(session("s1", "2026-01-01", 200.0, true))))
        assertEquals(1, m.sessions.size); assertEquals(200.0, m.sessions[0].updatedAt, 0.0); assertTrue(m.sessions[0].finished)
    }

    @Test fun tieBreaksOnFinishedFlag() =
        assertTrue(GitHubSync.mergeBackups(Backup(sessions = listOf(session("s1", "2026-01-01", 100.0, true))), Backup(sessions = listOf(session("s1", "2026-01-01", 100.0, false)))).sessions[0].finished)

    @Test fun unionsDistinctSessionIds() =
        assertEquals(setOf("a", "b"), GitHubSync.mergeBackups(Backup(sessions = listOf(session("a", "2026-01-01", 100.0))), Backup(sessions = listOf(session("b", "2026-01-02", 100.0)))).sessions.map { it.id }.toSet())

    @Test fun deletionWinsOverLiveRemoteCopy() {
        val m = GitHubSync.mergeBackups(Backup(deletedIds = listOf(DeletedId("s1", 500.0))), Backup(sessions = listOf(session("s1", "2026-01-01", 999.0))))
        assertTrue(m.sessions.isEmpty()); assertEquals(listOf("s1"), m.deletedIds.map { it.id })
    }

    @Test fun tombstoneUnionKeepsNewestTimestamp() =
        assertEquals(900.0, GitHubSync.mergeBackups(Backup(deletedIds = listOf(DeletedId("s1", 100.0))), Backup(deletedIds = listOf(DeletedId("s1", 900.0)))).deletedIds[0].at, 0.0)

    @Test fun dedupsEventsByIsoAndType() {
        val e = Event(1.0, "2026-01-01T00:00:00Z", "app_open")
        assertEquals(1, GitHubSync.mergeBackups(Backup(events = listOf(e)), Backup(events = listOf(e))).events.size)
    }

    @Test fun aiSettingsNewestWins() =
        assertEquals("remote profile", GitHubSync.mergeBackups(Backup(aiSettings = AISettings(profile = "local profile", updatedAt = 100.0)), Backup(aiSettings = AISettings(profile = "remote profile", updatedAt = 200.0))).aiSettings.profile)

    @Test fun healthRowsFreshestWins() =
        assertEquals(55.0, GitHubSync.mergeBackups(Backup(health = listOf(HealthRow("2026-01-01", hrv = 40.0, receivedAt = 100.0))), Backup(health = listOf(HealthRow("2026-01-01", hrv = 55.0, receivedAt = 200.0)))).health[0].hrv!!, 0.0)

    @Test fun readmeOnEmptyHistory() = assertTrue(GitHubSync.buildReadme(emptyList()).contains("0 sessions"))
}

/** Port of HealthKitSyncTests.swift for the Health Connect reader's pure parts. */
class HealthConnectSyncTest {
    @Test fun overlappingSleepFromWatchAndPhoneCountsOnce() {
        fun iv(a: Double, b: Double) = a * 3600 to b * 3600
        assertEquals(8.0, HealthConnectSync.mergedDurationSec(listOf(iv(0.0, 8.0), iv(0.5, 7.5))) / 3600, 0.001)
        assertEquals(7.5, HealthConnectSync.mergedDurationSec(listOf(iv(0.0, 4.0), iv(4.5, 8.0))) / 3600, 0.001)
        assertEquals(0.0, HealthConnectSync.mergedDurationSec(emptyList()), 0.0)
    }

    @Test fun shortcutTextParsesBackToTheSameNumbers() {
        val m = HealthConnectSync.DayMetrics(hrv = 51.8, rhr = 67.3, steps = 19712.0, sleepH = 7.25, vo2max = 33.6, kcal = 967.0, exerciseMin = 87.0, distKm = 13.58, respRate = 18.4, wristC = 35.87)
        val n = Stats.parseHealthNumbers(m.shortcutText)
        assertEquals(51.8, n.hrv!!, 0.0); assertEquals(67.3, n.rhr!!, 0.0); assertEquals(19712.0, n.steps!!, 0.0)
        assertEquals(7.3, n.sleepH!!, 0.0); assertEquals(33.6, n.vo2max!!, 0.0); assertEquals(967.0, n.kcal!!, 0.0)
        assertEquals(87.0, n.exerciseMin!!, 0.0); assertEquals(13.58, n.distKm!!, 0.0); assertEquals(18.4, n.respRate!!, 0.0); assertEquals(35.87, n.wristC!!, 0.0)
    }

    @Test fun missingMetricsAreLeftOutNotMisread() {
        val m = HealthConnectSync.DayMetrics(hrv = 40.0, distKm = 1.54)
        assertFalse(m.shortcutText.contains("ExerciseMin"))
        assertNull(Stats.parseHealthNumbers(m.shortcutText).exerciseMin)
        assertTrue(HealthConnectSync.DayMetrics().isEmpty)
    }
}

/** Port of StreakMilestoneTests.swift — streak milestones count against your own weekly target. */
class StreakMilestoneTest {
    private fun history(): List<Session> {
        val monday = LocalDate.parse(Stats.mondayOf(Helpers.todayStr()))
        return (1..12).flatMap { w ->
            (0 until 3).map { d ->
                val iso = monday.minusWeeks(w.toLong()).plusDays(d.toLong()).toString()
                Session("$iso#$d", iso, 0.0, null, Plan(sessionType = "Push", exercises = listOf(Plan.Exercise(name = "Bench Press", sets = 1, reps = "5"))),
                    listOf(listOf(SetLog("60", "5", true))), true)
            }
        }
    }

    private fun streakMilestone(target: Int): Int {
        LocalStore.updateAISettings { it.copy(weeklyTarget = target) }
        return Dashboard.ladders(history()).first { it.key == "streak" }.value
    }

    @Test fun streakMilestonesUseYourTarget() {
        Cloud.offline = true
        val h = history()
        assertEquals(Stats.weekStats(h, 3).streak, streakMilestone(3))
        assertEquals(Stats.weekStats(h, 4).streak, streakMilestone(4))
        assertTrue(streakMilestone(3) > streakMilestone(4))
    }
}
