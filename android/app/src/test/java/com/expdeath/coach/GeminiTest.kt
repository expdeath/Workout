package com.expdeath.coach

import com.expdeath.coach.ai.Gemini
import com.expdeath.coach.ai.j
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.SavedWorkout
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.Workouts
import com.expdeath.coach.persistence.AIConsent
import com.expdeath.coach.persistence.Prefs
import com.expdeath.coach.stats.Helpers
import com.expdeath.coach.stats.nowMs
import com.expdeath.coach.sync.Cloud
import com.expdeath.coach.sync.GitHubSync
import com.expdeath.coach.sync.Http
import com.expdeath.coach.sync.HttpResponse
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.LocalDate

private fun reply(text: String) = HttpResponse(200, j(mapOf("candidates" to listOf(mapOf("content" to mapOf("parts" to listOf(mapOf("text" to text))), "finishReason" to "STOP")))).toJsonString().toByteArray())

private fun bench(w: String, reps: String, date: String) = Session("$date#1", date, 0.0, null,
    Plan(sessionType = "Push", exercises = listOf(Plan.Exercise(name = "Bench Press", sets = 3, reps = "8-10")), estTimeMin = 45),
    listOf(listOf(SetLog(w, reps, true))), true)

/** Port of GeminiClientTests.swift — sanitizePlan is the deterministic
 *  safety net on whatever the model returns. */
class SanitizeTest {
    @Before fun setUp() { Cloud.offline = true }

    private fun plan(w: String) = Plan(sessionType = "Push", exercises = listOf(Plan.Exercise(name = "Bench Press", sets = 3, reps = "8-10", suggestedWeight = w)), estTimeMin = 45)

    @Test fun capsSuggestedWeightThatJumpsTooFar() =
        // cap = min(max(60*1.15, 62.5), 200) = 69 → nearest 2.5 = 70
        assertEquals("70kg", Gemini.sanitizePlan(plan("120kg"), listOf(bench("60", "10", "2026-01-01")), Checkin(timeAvail = "60")).exercises[0].suggestedWeight)

    @Test fun leavesReasonableSuggestionUntouched() =
        assertEquals("62.5kg", Gemini.sanitizePlan(plan("62.5kg"), listOf(bench("60", "10", "2026-01-01")), Checkin(timeAvail = "60")).exercises[0].suggestedWeight)

    @Test fun noHistoryAllowsAnyReasonableWeight() =
        assertEquals("40kg", Gemini.sanitizePlan(plan("40kg"), emptyList(), Checkin(timeAvail = "60")).exercises[0].suggestedWeight)

    @Test fun capsExerciseCountAtSix() =
        assertEquals(6, Gemini.sanitizePlan(Plan(sessionType = "Push", exercises = (1..9).map { Plan.Exercise(name = "Exercise $it", sets = 3, reps = "10") }, estTimeMin = 45), emptyList(), Checkin(timeAvail = "60")).exercises.size)

    @Test fun capsEstTimeToTheCheckinBudget() =
        assertEquals(69, Gemini.sanitizePlan(Plan(sessionType = "Push", exercises = listOf(Plan.Exercise(name = "Bench", sets = 3, reps = "10")), estTimeMin = 500), emptyList(), Checkin(timeAvail = "45")).estTimeMin)

    @Test fun userMessageEdgeCases() {
        assertTrue(Gemini.buildUserMessage(Checkin(), emptyList(), emptyList()).contains("No logged sessions yet"))
        assertTrue(Gemini.buildUserMessage(Checkin(wish = "cardio"), emptyList(), emptyList()).contains("CARDIO day"))
    }

    @Test fun truncatedReplyIsRepaired() {
        val p = Gemini.repairAndDecodePlan("```json\n{\"sessionType\":\"Push\",\"estTimeMin\":40,\"exercises\":[{\"name\":\"Bench Press\",\"sets\":3,\"reps\":\"8")
        assertEquals("Bench Press", p.exercises[0].name)
    }
}

/** Ports GeminiFallbackTests.swift, ProTests.swift and WorkoutsTests.swift —
 *  model fallback, COACH Pro routing, consent, and the saved-workout library,
 *  with every request answered by a stub (no network). */
class CoachNetworkTest {
    private val requested = ArrayList<String>()
    private val headers = ArrayList<Map<String, String>>()
    private val bodies = ArrayList<String>()

    @Before fun setUp() {
        Cloud.offline = true
        Cloud.setSharedGeminiKey("stub-key")
        Cloud.debugSetPro(emptyMap())
        AIConsent.set(true)
        for (k in Cloud.stateKeys()) if (k.startsWith("workout-")) Cloud.setState(k, null)
    }

    @After fun tearDown() {
        Http.stub = null
        Cloud.debugIdToken = null
        Cloud.debugSetPro(emptyMap())
    }

    private fun stub(answer: (url: String) -> HttpResponse) {
        Http.stub = { url, _, h, body ->
            requested.add(url); headers.add(h); bodies.add(body?.toString(Charsets.UTF_8) ?: "")
            answer(url)
        }
    }

    private val plan = """{"sessionType":"Push","title":"Stub push","estTimeMin":45,"exercises":[{"name":"Bench Press","sets":3,"reps":"8-10","rpe":"8","rest":"90s"}]}"""
    private fun model(url: String) = url.substringAfterLast("/").substringBefore(":")

    @Test fun rateLimitedPrimarySwitchesToNextModelAtOnce() = runBlocking {
        stub { url ->
            if (model(url) == "gemini-3.5-flash") HttpResponse(429, """{"error":{"code":429,"message":"Quota exceeded. Please retry in 30s."}}""".toByteArray())
            else reply(plan)
        }
        val started = System.currentTimeMillis()
        assertEquals("Stub push", Gemini.generateWorkoutPlan(Checkin(), emptyList()).title)
        assertEquals(listOf("gemini-3.5-flash", "gemini-3.1-flash-lite"), requested.map { model(it) })
        assertTrue("no 30–45s wait before switching", System.currentTimeMillis() - started < 5000)
    }

    @Test fun healthyPrimaryIsUsedFirst() = runBlocking {
        stub { reply(plan) }
        Gemini.generateWorkoutPlan(Checkin(), emptyList())
        assertEquals(listOf("gemini-3.5-flash"), requested.map { model(it) })
    }

    @Test fun noKeyAndNoProMeansNoAI() = runBlocking {
        stub { reply(plan) }
        Cloud.setSharedGeminiKey("")
        assertFalse(Cloud.aiReady)
        try { Gemini.generateWorkoutPlan(Checkin(), emptyList()); fail() } catch (_: Exception) {}
        assertTrue(requested.isEmpty())
    }

    @Test fun proSendsEveryRequestThroughTheServer() = runBlocking {
        stub { reply("""{"sessionType":"Push","title":"Server plan","estTimeMin":40,"exercises":[{"name":"Bench Press","sets":3,"reps":"8"}]}""") }
        Cloud.setSharedGeminiKey("")
        Cloud.debugIdToken = "test-id-token"
        Cloud.debugSetPro(mapOf("pro" to JSONValue.Bool(true), "expiresAt" to JSONValue.Num(nowMs() + 86_400_000)))
        assertTrue("Pro works without a key", Cloud.aiReady)
        assertEquals("Server plan", Gemini.generateWorkoutPlan(Checkin(), emptyList()).title)
        assertEquals("https://europe-west2-heath-9a322.cloudfunctions.net/coach", requested[0])
        assertEquals("Bearer test-id-token", headers[0]["Authorization"])
        assertNull("no key leaves the phone", headers[0]["X-goog-api-key"])
        assertTrue(bodies[0].contains("\"model\":\"gemini-3.5-flash\"")); assertTrue(bodies[0].contains("\"contents\""))
    }

    @Test fun serverRefusalStopsTheModelLadder() = runBlocking {
        stub { HttpResponse(402, """{"error":{"code":402,"message":"COACH Pro isn’t active on this account."}}""".toByteArray()) }
        Cloud.debugIdToken = "t"
        Cloud.debugSetPro(mapOf("pro" to JSONValue.Bool(true)))
        try { Gemini.generateWorkoutPlan(Checkin(), emptyList()); fail("should refuse") } catch (e: Exception) {
            assertEquals("COACH Pro isn’t active on this account.", e.message)
        }
        assertEquals("not retried on the other models", 1, requested.size)
    }

    @Test fun expiredProFallsBackToTheKey() {
        Cloud.debugSetPro(mapOf("pro" to JSONValue.Bool(true), "expiresAt" to JSONValue.Num(1000.0)))
        assertFalse(Cloud.proActive)
    }

    @Test fun nothingGoesToGeminiWithoutConsent() = runBlocking {
        stub { reply(plan) }
        AIConsent.set(false)
        try { Gemini.generateWorkoutPlan(Checkin(), emptyList()); fail("should refuse") } catch (e: Exception) {
            assertEquals(Gemini.GeminiError.NoConsent().message, e.message)
        }
        try { Gemini.buildWorkouts("core every day", null, "me", emptyList()); fail("should refuse") } catch (_: Exception) {}
        assertTrue("no request was made", requested.isEmpty())
        Cloud.setState("aiConsent", null)
        assertFalse("never asked → the consent screen shows", AIConsent.answered)
        AIConsent.set(true)
        assertTrue(AIConsent.answered && AIConsent.allowed)
    }

    // ── Saved workouts (WorkoutsTests.swift) ──

    private val todayWD = LocalDate.now().dayOfWeek.value % 7

    private fun upperA(adapt: Boolean = false) = SavedWorkout(name = "Upper A", source = "trainer", trainer = "Sam", adapt = adapt, days = listOf(todayWD), exercises = listOf(
        SavedWorkout.Exercise("Bench Press", 4, "6"), SavedWorkout.Exercise("Barbell Row", 3, "8", "60kg"),
    ))

    @Test fun decodesTheWebAppsShape() {
        val w = SavedWorkout.fromJson(JSONValue.parse("""{"id":"abc1","name":"Daily core","kind":"addon","source":"trainer","trainer":"Sam","notes":"","adapt":false,"days":[],"exercises":[{"name":"Plank","sets":3,"reps":"45s","weight":"","rest":"30s","notes":""}],"createdAt":1791520416446,"updatedAt":1791520416446}""")!!)!!
        assertTrue(w.isAddOn); assertEquals("45s", w.exercises[0].reps); assertEquals("Every day", Workouts.daysLabel(w))
    }

    @Test fun saveListScheduleDelete() {
        val s = Workouts.save(upperA())
        val a = Workouts.save(SavedWorkout(name = "Daily core", kind = "addon", exercises = listOf(SavedWorkout.Exercise("Plank", 3, "45s"))))
        Workouts.save(SavedWorkout(name = "Lower B", days = listOf((todayWD + 1) % 7), exercises = listOf(SavedWorkout.Exercise("Back Squat"))))
        assertFalse(s.id.isEmpty())
        assertEquals("sessions first, then add-ons", listOf("Lower B", "Upper A", "Daily core"), Workouts.list().map { it.name })
        val today = Workouts.scheduledFor()
        assertEquals(listOf("Upper A"), today.sessions.map { it.name }); assertEquals(listOf("Daily core"), today.addOns.map { it.name })
        Workouts.delete(a.id)
        assertNull(Workouts.get(a.id))
    }

    @Test fun keepExactHoldsTheCoachToTheWrittenWorkout() {
        val coach = Plan(sessionType = "Full Body", title = "Coach version", exercises = listOf(
            Plan.Exercise(name = "Back Squat", sets = 5, reps = "5", suggestedWeight = "90kg"),
            Plan.Exercise(name = "Bench Press", sets = 2, reps = "10", rpe = "7", notes = "Pause on chest", suggestedWeight = "72.5kg"),
        ))
        val p = Workouts.enforceExact(coach, upperA(), emptyList())
        assertEquals("Upper A", p.title)
        assertEquals(listOf("Bench Press", "Barbell Row"), p.exercises.map { it.name })
        assertEquals(4, p.exercises[0].sets); assertEquals("6", p.exercises[0].reps)
        assertEquals("72.5kg", p.exercises[0].suggestedWeight); assertEquals("60kg", p.exercises[1].suggestedWeight)
        assertEquals("Pause on chest", p.exercises[0].notes)
    }

    @Test fun withoutTheCoachWeightsComeFromHistory() {
        val prior = Session("p1", "2026-01-01", 0.0, null, Plan(sessionType = "Push", exercises = listOf(Plan.Exercise(name = "Bench Press", sets = 3, reps = "8-10"))),
            listOf(listOf(SetLog("60", "10", true), SetLog("60", "10", true))), true)
        val w = upperA().let { it.copy(exercises = it.exercises.mapIndexed { i, e -> if (i == 0) e.copy(reps = "8-10") else e }) }
        val p = Workouts.templateToPlan(w, listOf(prior))
        assertEquals("62.5kg", p.exercises[0].suggestedWeight); assertEquals("60kg", p.exercises[1].suggestedWeight)
        assertTrue(p.reasoning.contains("Sam"))
    }

    @Test fun addOnsGoOnTheEnd() {
        val core = SavedWorkout(name = "Daily core", kind = "addon", exercises = listOf(SavedWorkout.Exercise("Plank", 3, "45s"), SavedWorkout.Exercise("Dead Bug", 2, "10")))
        val p = Workouts.appendAddOns(Workouts.templateToPlan(upperA(), emptyList()), listOf(core), emptyList())
        assertEquals(listOf("Bench Press", "Barbell Row", "Plank", "Dead Bug"), p.exercises.map { it.name })
        assertTrue(p.exercises[2].notes.startsWith("Add-on · Daily core"))
    }

    @Test fun promptTellsTheCoachWhichMode() {
        assertTrue(Gemini.buildUserMessage(Checkin(), emptyList(), template = upperA()).contains("Use EXACTLY these exercises"))
        assertTrue(Gemini.buildUserMessage(Checkin(), emptyList(), template = upperA(true)).contains("ADAPTED TO TODAY"))
        assertTrue(Gemini.buildUserMessage(Checkin(), emptyList()).contains("Decide the right session for today"))
    }

    @Test fun coachBuildsWorkoutsFromTextAndPhoto() = runBlocking {
        stub { reply("""{"message":"Built two.","workouts":[{"name":"Lower B","kind":"session","days":["Mon"],"notes":"","exercises":[{"name":"Back Squat","sets":4,"reps":"6","weight":"85kg","rest":"3 min","notes":""}]},{"name":"Daily core","kind":"addon","days":[],"notes":"","exercises":[{"name":"Plank","sets":3,"reps":"45s","weight":"","rest":"","notes":""}]}]}""") }
        val res = Gemini.buildWorkouts("Day B Monday: squat 4x6 85kg", byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()), "trainer", emptyList())
        assertEquals(listOf("Lower B", "Daily core"), res.workouts.map { it.name })
        assertEquals(listOf(1), res.workouts[0].days); assertTrue(res.workouts[1].isAddOn); assertEquals("Built two.", res.message)
        assertTrue("the photo is sent to the coach", bodies[0].contains("inline_data"))
        assertTrue(bodies[0].contains("Transcribe it faithfully"))
    }

    @Test fun backupCarriesTheLibraryAndSwitches() {
        val b = Backup(workouts = listOf(SavedWorkout(id = "b", name = "B").toJson(), SavedWorkout(id = "a", name = "A").toJson()), prefs = JSONValue.obj("restSound" to JSONValue.Bool(false)))
        val round = Backup.fromJson(JSONValue.parse(GitHubSync.normalizeBackup(b).toJson().toJsonString())!!)!!
        assertEquals(2, round.workouts.size); assertEquals("sorted by id", "a", round.workouts[0].obj!!["id"]!!.string)
        assertEquals(JSONValue.obj("restSound" to JSONValue.Bool(false)), round.prefs)
        val empty = GitHubSync.normalizeBackup(Backup()).toJson().toJsonString()
        assertFalse(empty.contains("workouts")); assertFalse(empty.contains("prefs"))
    }

    @Test fun switchesDefaultOnAndSave() {
        Cloud.setState("prefs", null)
        assertTrue(Prefs.isOn("restSound"))
        Prefs.set("restSound", false)
        assertFalse(Prefs.isOn("restSound")); assertTrue(Prefs.isOn("debrief"))
        Cloud.setState("prefs", null)
    }

    @Test fun inboxFileBecomesTodaysHealthRow() {
        GitHubSync.ingestInboxFile("health-${Helpers.todayStr()}.json", """{"hrv":48,"rhr":57,"sleepH":7.5,"weightKg":80.2}""")
        val row = com.expdeath.coach.persistence.LocalStore.backup.health.first { it.date == Helpers.todayStr() }
        assertEquals(48.0, row.hrv!!, 0.0); assertEquals(80.2, row.weightKg!!, 0.0)
        assertEquals("HRV 48 ms · RHR 57 · Sleep 7.5h · Weight 80.2kg", Cloud.stateValue("healthText-${Helpers.todayStr()}")!!.string)
    }
}
