package com.expdeath.coach

import com.expdeath.coach.models.AISettings
import com.expdeath.coach.models.Backup
import com.expdeath.coach.models.Checkin
import com.expdeath.coach.models.Event
import com.expdeath.coach.models.HealthRow
import com.expdeath.coach.models.JSONValue
import com.expdeath.coach.models.Plan
import com.expdeath.coach.models.Session
import com.expdeath.coach.models.SetLog
import com.expdeath.coach.models.toJson
import com.expdeath.coach.sync.FirestoreCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

private fun json(s: String): JSONValue = JSONValue.parse(s)!!

/** Port of LenientDecodingTests.swift — real shapes from synced data must
 *  decode (missing keys, mixed types) and round-trip without losing a key. */
class LenientDecodingTest {
    @Test fun setLogDecodesQuickCardioShapeWithNoWeightOrReps() {
        // logQuickCardio literally writes `{ time, dist, done }`
        val set = SetLog.fromJson(json("""{"time":"32","dist":"5.1","done":true}"""))!!
        assertEquals("32", set.time); assertEquals("5.1", set.dist); assertTrue(set.done)
        assertEquals("", set.weight); assertEquals("", set.reps)
    }

    @Test fun setLogDecodesStrengthShapeWithNoTimeDistEffort() {
        val set = SetLog.fromJson(json("""{"weight":"60","reps":"8","done":true}"""))!!
        assertEquals("60", set.weight); assertEquals("8", set.reps); assertEquals("", set.effort)
    }

    @Test fun checkinDecodesWithoutNewerPrioritizeMuscleField() {
        val ci = Checkin.fromJson(json("""{"energy":8,"sleep":"Great","soreness":"None","soreAreas":"","backTight":false,"timeAvail":"45","wish":"","bodyKg":"","notes":""}"""))!!
        assertEquals(8, ci.energy); assertEquals("", ci.prioritizeMuscle)
    }

    @Test fun aiSettingsDecodesPartiallyMergedObject() {
        val s = AISettings.fromJson(json("""{"profile":"Recreational lifter","updatedAt":1735689600000}"""))!!
        assertEquals("Recreational lifter", s.profile); assertEquals("", s.goals); assertEquals(emptyMap<String, String>(), s.cueNotes)
    }

    @Test fun planDecodesWithOnlySchemaRequiredFields() {
        val plan = Plan.fromJson(json("""{"sessionType":"Push","exercises":[{"name":"Bench Press","sets":3,"reps":"8-10"}],"estTimeMin":50}"""))!!
        assertEquals("Push", plan.sessionType); assertEquals(1, plan.exercises.size)
        assertEquals("Session chosen from your check-in and recent log.", plan.reasoning)
        assertEquals(50, plan.recoveryScore)
    }

    @Test fun restDayAllowsEmptyExercises() {
        assertTrue(Plan.fromAI("""{"sessionType":"Rest Day","exercises":[],"estTimeMin":0}""").exercises.isEmpty())
    }

    @Test fun nonRestDayWithNoExercisesIsRejectedFromTheAIButStillLoadsFromStorage() {
        assertThrows(Exception::class.java) { Plan.fromAI("""{"sessionType":"Push","exercises":[],"estTimeMin":50}""") }
        assertNotNull(Plan.fromJson(json("""{"sessionType":"Push","exercises":[],"estTimeMin":50}""")))
    }

    @Test fun backupDecodesLegacyFileMissingNewerTopLevelFields() {
        val b = Backup.fromJson(json("""{"app":"coach","version":1,"sessions":[]}"""))!!
        assertTrue(b.health.isEmpty()); assertTrue(b.deletedIds.isEmpty()); assertEquals(AISettings(), b.aiSettings)
    }

    @Test fun sessionDecodesRealShapeWithoutDeletedOrUpdatedAtKeys() {
        val s = Session.fromJson(json("""{"id":"2026-01-01#123","date":"2026-01-01","startedAt":123,"plan":{"sessionType":"Rest Day","exercises":[],"estTimeMin":0},"log":[],"finished":false}"""))!!
        assertFalse(s.deleted); assertEquals(0.0, s.updatedAt, 0.0); assertNull(s.checkin)
    }

    @Test fun numericRpeDecodesAndSurvivesUnchanged() {
        val raw = """{"id":"2026-08-01#1","date":"2026-08-01","startedAt":1,"plan":{"sessionType":"Push","exercises":[{"name":"Bench","sets":3,"reps":"8","rpe":8}],"estTimeMin":50},"log":[[{"weight":"60","reps":"8","done":true}]],"finished":true,"updatedAt":5}"""
        val s = Session.fromJson(json(raw))!!
        assertEquals("8", s.plan.exercises[0].rpe)
        assertEquals(json(raw), s.toJson())
    }

    @Test fun unknownKeysAndAbsentDefaultsSurviveRoundTrip() {
        val raw = """{"id":"x","date":"2026-08-02","plan":{"sessionType":"Run","exercises":[],"futurePlanKey":{"a":[1,2]}},"log":[[{"time":"30","dist":"5","done":true,"hr":151}]],"futureKey":"kept","backfilled":true}"""
        assertEquals(json(raw), Session.fromJson(json(raw))!!.toJson())
    }

    @Test fun editWritesOnlyTheChangedField() {
        val raw = """{"id":"x","date":"2026-08-03","startedAt":1,"plan":{"sessionType":"Push","exercises":[{"name":"Bench","sets":3,"rpe":8,"extra":"keep"}]},"log":[[{"weight":"60","reps":"8","done":true,"note":"keep"}]],"updatedAt":5}"""
        val s = Session.fromJson(json(raw))!!
        val edited = s.copy(log = listOf(listOf(s.log[0][0].copy(weight = "62.5"))))
        val out = edited.toJson().obj!!
        val set = out["log"]!!.array!![0].array!![0].obj!!
        assertEquals("62.5", set["weight"]!!.string); assertEquals("keep", set["note"]!!.string)
        val ex = out["plan"]!!.obj!!["exercises"]!!.array!![0].obj!!
        assertEquals("an untouched number must stay a number", JSONValue.Num(8.0), ex["rpe"])
        assertEquals("keep", ex["extra"]!!.string)
    }

    @Test fun healthRowKeepsEveryWatchMetric() {
        val raw = """{"date":"2026-09-16","hrv":51.5,"rhr":65.75,"steps":2125,"sleepH":6.5,"vo2max":33.5,"kcal":359.046,"exerciseMin":12,"distKm":1.54,"respRate":19,"wristC":35.6,"spo2":97,"raw":"…","receivedAt":1789570663885}"""
        val h = HealthRow.fromJson(json(raw))!!
        assertEquals(359.046, h.kcal!!, 0.0); assertEquals(97.0, h.spo2!!, 0.0)
        assertEquals(json(raw), h.toJson())
    }

    @Test fun aiSettingsKeepsGymSetupAndAddsNoKeys() {
        val raw = """{"barKg":20,"plates":"25, 20, 15, 10, 5, 2.5, 1.25","updatedAt":1784324080942}"""
        val s = AISettings.fromJson(json(raw))!!
        assertEquals(20.0, s.barKg!!, 0.0); assertEquals("25, 20, 15, 10, 5, 2.5, 1.25", s.plates)
        assertEquals(json(raw), s.toJson())
    }

    @Test fun malformedBackupRowIsKeptNotDropped() {
        val b = Backup.fromJson(json("""{"app":"coach","version":4,"aiSettings":{},"deletedIds":[],"health":[],"sessions":[{"id":"ok","date":"2026-08-04","plan":{"sessionType":"Push"},"log":[]},{"no":"date"}],"events":[]}"""))!!
        assertEquals(1, b.sessions.size); assertEquals(1, b.unparsed.sessions.size)
        assertEquals(2, b.toJson().v["sessions"]!!.array!!.size)
    }
}

/** Port of FirestoreCodecTests.swift — the same documents as
 *  src/db/firestoreCodec.js, lossless for any JSON. */
class FirestoreCodecTest {
    /** The trip through Firestore: maps/lists of Long, Double, Boolean, String. */
    private fun throughFirestore(v: Any?): Any? = v

    @Test fun nestedArraysAreWrappedLikeTheWebCodec() {
        @Suppress("UNCHECKED_CAST")
        val enc = FirestoreCodec.encode(json("""{"log":[[{"weight":"60"}],[]]}""")) as Map<String, Any?>
        val log = enc["log"] as List<*>
        assertEquals(1, ((log[0] as Map<*, *>)["__a"] as List<*>).size)
        assertNotNull((log[1] as Map<*, *>)["__a"])
    }

    @Test fun badKeysUseTheEscapedMapForm() {
        assertEquals(setOf("__m"), (FirestoreCodec.encode(json("""{"":1,"__x__":2}""")) as Map<*, *>).keys)
    }

    @Test fun roundTripOfEdgeCases() {
        val v = json("""{"a":[[1,[2]],[]],"":1,"__x__":{"__a":[3]},"n":null,"s":"é/ü","e":{},"t":true,"f":false,"one":1,"half":0.5,"big":1789570663885}""")
        assertEquals(v, FirestoreCodec.decode(throughFirestore(FirestoreCodec.encode(v))))
    }

    @Test fun booleansAndNumbersStayDistinct() {
        val v = json("""{"done":true,"sets":1,"zero":0,"no":false}""")
        assertEquals(v, FirestoreCodec.decode(FirestoreCodec.encode(v)))
    }

    @Test fun wholeNumbersAreWrittenAsIntegers() {
        assertEquals(1789570663885L, FirestoreCodec.encode(JSONValue.Num(1789570663885.0)))
        assertEquals(51.77, FirestoreCodec.encode(JSONValue.Num(51.77)))
    }

    @Test fun docIdsMatchTheWebCodec() {
        assertEquals("2026-10-07#1784468740277", FirestoreCodec.docId("2026-10-07#1784468740277"))
        assertEquals("a%2Fb%25c", FirestoreCodec.docId("a/b%c"))
        assertEquals("%", FirestoreCodec.docId(""))
        assertEquals("%..", FirestoreCodec.docId(".."))
        assertEquals("%__name__", FirestoreCodec.docId("__name__"))
        assertEquals("2026-10-07T06:06:52.123Z|app_open", FirestoreCodec.eventDocId(Event(1.0, "2026-10-07T06:06:52.123Z", "app_open")))
    }

    @Test fun sessionDocumentRoundTripsLosslessly() {
        val raw = """{"id":"2026-08-01#1","date":"2026-08-01","plan":{"sessionType":"Push","exercises":[{"name":"Bench","rpe":8,"extra":"kept"}]},"log":[[{"weight":"60","done":true,"hr":151}]],"futureKey":[1,[2]]}"""
        val s = Session.fromJson(json(raw))!!
        val doc = FirestoreCodec.document(s.toJson())
        val back = Session.fromJson(FirestoreCodec.decode(doc))!!
        assertEquals("unknown keys and odd types survive the database", json(raw), back.toJson())
    }
}
