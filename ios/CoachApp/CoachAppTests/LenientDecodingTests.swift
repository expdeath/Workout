import XCTest
@testable import CoachApp

/// Swift's synthesized Decodable throws on a missing JSON key even when
/// the property has a default value — it only skips missing keys for
/// Optional properties. Every model that can come from real synced data
/// (as opposed to data this app itself just wrote) needs a custom
/// lenient decoder instead. These tests use real shapes pulled from the
/// web app's source, not hypothetical ones.
final class LenientDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testSetLog_decodesQuickCardioShapeWithNoWeightOrReps() throws {
        // src/App.jsx logQuickCardio literally writes `{ time, dist, done }`
        // — no weight/reps/effort keys at all.
        let set = try decode(SetLog.self, #"{"time":"32","dist":"5.1","done":true}"#)
        XCTAssertEqual(set.time, "32")
        XCTAssertEqual(set.dist, "5.1")
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.weight, "")
        XCTAssertEqual(set.reps, "")
    }

    func testSetLog_decodesOrdinaryStrengthShapeWithNoTimeDistEffort() throws {
        let set = try decode(SetLog.self, #"{"weight":"60","reps":"8","done":true}"#)
        XCTAssertEqual(set.weight, "60")
        XCTAssertEqual(set.reps, "8")
        XCTAssertEqual(set.effort, "")
    }

    func testCheckin_decodesWithoutNewerPrioritizeMuscleField() throws {
        let ci = try decode(Checkin.self, #"{"energy":8,"sleep":"Great","soreness":"None","soreAreas":"","backTight":false,"timeAvail":"45","wish":"","bodyKg":"","notes":""}"#)
        XCTAssertEqual(ci.energy, 8)
        XCTAssertEqual(ci.prioritizeMuscle, "")
    }

    func testAISettings_decodesPartiallyMergedObject() throws {
        // setAISettings() shallow-merges — a user who has only ever set
        // a profile has an object with just {profile, updatedAt}.
        let s = try decode(AISettings.self, #"{"profile":"Recreational lifter","updatedAt":1735689600000}"#)
        XCTAssertEqual(s.profile, "Recreational lifter")
        XCTAssertEqual(s.goals, "")
        XCTAssertEqual(s.cueNotes, [:])
    }

    func testPlan_decodesWithOnlySchemaRequiredFields() throws {
        // PLAN_SCHEMA only requires sessionType/exercises/estTimeMin —
        // Gemini is free to omit everything else.
        let plan = try decode(Plan.self, #"{"sessionType":"Push","exercises":[{"name":"Bench Press","sets":3,"reps":"8-10"}],"estTimeMin":50}"#)
        XCTAssertEqual(plan.sessionType, "Push")
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.reasoning, "Session chosen from your check-in and recent log.")
        XCTAssertEqual(plan.recoveryScore, 50)
    }

    func testPlan_restDayAllowsEmptyExercises() throws {
        let plan = try decode(Plan.self, #"{"sessionType":"Rest Day","exercises":[],"estTimeMin":0}"#)
        XCTAssertTrue(plan.exercises.isEmpty)
    }

    func testPlan_nonRestDayWithNoExercisesThrows() {
        // Mirrors validatePlan() in parser.js: a lifting day with zero
        // exercises means a truncated response — must throw so the
        // caller falls back to the next model.
        XCTAssertThrowsError(try Plan.fromAI(Data(#"{"sessionType":"Push","exercises":[],"estTimeMin":50}"#.utf8)))
        // …but a stored plan like that still loads (history must never fail to decode)
        XCTAssertNoThrow(try decode(Plan.self, #"{"sessionType":"Push","exercises":[],"estTimeMin":50}"#))
    }

    func testBackup_decodesLegacyFileMissingNewerTopLevelFields() throws {
        // A repo whose backup.json predates the health store / deletedIds
        // migration.
        let b = try decode(Backup.self, #"{"app":"coach","version":1,"sessions":[]}"#)
        XCTAssertTrue(b.health.isEmpty)
        XCTAssertTrue(b.deletedIds.isEmpty)
        XCTAssertEqual(b.aiSettings, AISettings())
    }

    func testSession_decodesRealShapeWithoutDeletedOrUpdatedAtKeys() throws {
        let json = """
        {"id":"2026-01-01#123","date":"2026-01-01","startedAt":123,
         "plan":{"sessionType":"Rest Day","exercises":[],"estTimeMin":0},
         "log":[],"finished":false}
        """
        let s = try decode(Session.self, json)
        XCTAssertFalse(s.deleted)
        XCTAssertEqual(s.updatedAt, 0)
        XCTAssertNil(s.checkin)
    }

    // ── Lossless round trips (RawPreserving.swift) ───────────────
    // Regressions from real synced data (2026-10-07): two of four real
    // accounts failed to decode at all (numeric `rpe`), and re-encoding
    // dropped fields the models didn't declare.

    /// JSON → model → JSON, compared as parsed objects (key order free).
    func roundTrip<T: Codable>(_ type: T.Type, _ json: String) throws -> NSDictionary {
        let model = try decode(type, json)
        let out = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model))
        return out as! NSDictionary
    }

    func object(_ json: String) -> NSDictionary {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! NSDictionary
    }

    func testSession_numericRpeDecodesAndSurvivesUnchanged() throws {
        let json = #"{"id":"2026-08-01#1","date":"2026-08-01","startedAt":1,"plan":{"sessionType":"Push","exercises":[{"name":"Bench","sets":3,"reps":"8","rpe":8}],"estTimeMin":50},"log":[[{"weight":"60","reps":"8","done":true}]],"finished":true,"updatedAt":5}"#
        let s = try decode(Session.self, json)
        XCTAssertEqual(s.plan.exercises[0].rpe, "8")
        XCTAssertEqual(try roundTrip(Session.self, json), object(json))
    }

    func testSession_unknownKeysAndAbsentDefaultsSurviveRoundTrip() throws {
        // no `deleted`, no `checkin`, plan without reasoning/recoveryScore,
        // plus keys no model declares — none may be added or dropped
        let json = #"{"id":"x","date":"2026-08-02","plan":{"sessionType":"Run","exercises":[],"futurePlanKey":{"a":[1,2]}},"log":[[{"time":"30","dist":"5","done":true,"hr":151}]],"futureKey":"kept","backfilled":true}"#
        XCTAssertEqual(try roundTrip(Session.self, json), object(json))
    }

    func testSession_editWritesOnlyTheChangedField() throws {
        let json = #"{"id":"x","date":"2026-08-03","startedAt":1,"plan":{"sessionType":"Push","exercises":[{"name":"Bench","sets":3,"rpe":8,"extra":"keep"}]},"log":[[{"weight":"60","reps":"8","done":true,"note":"keep"}]],"updatedAt":5}"#
        var s = try decode(Session.self, json)
        s.log[0][0].weight = "62.5"
        let out = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        let set = ((out["log"] as! [[Any]])[0][0]) as! [String: Any]
        XCTAssertEqual(set["weight"] as? String, "62.5")
        XCTAssertEqual(set["note"] as? String, "keep")
        let ex = ((out["plan"] as! [String: Any])["exercises"] as! [[String: Any]])[0]
        XCTAssertEqual(ex["rpe"] as? Int, 8, "an untouched number must stay a number")
        XCTAssertEqual(ex["extra"] as? String, "keep")
    }

    func testHealthRow_keepsEveryWatchMetric() throws {
        let json = #"{"date":"2026-09-16","hrv":51.5,"rhr":65.75,"steps":2125,"sleepH":6.5,"vo2max":33.5,"kcal":359.046,"exerciseMin":12,"distKm":1.54,"respRate":19,"wristC":35.6,"spo2":97,"raw":"…","receivedAt":1789570663885}"#
        let h = try decode(HealthRow.self, json)
        XCTAssertEqual(h.kcal, 359.046)
        XCTAssertEqual(h.spo2, 97)
        XCTAssertEqual(try roundTrip(HealthRow.self, json), object(json))
    }

    func testAISettings_keepsGymSetupAndAddsNoKeys() throws {
        let json = #"{"barKg":20,"plates":"25, 20, 15, 10, 5, 2.5, 1.25","updatedAt":1784324080942}"#
        let s = try decode(AISettings.self, json)
        XCTAssertEqual(s.barKg, 20)
        XCTAssertEqual(s.plates, "25, 20, 15, 10, 5, 2.5, 1.25")
        XCTAssertEqual(try roundTrip(AISettings.self, json), object(json))
    }

    func testBackup_malformedRowIsKeptNotDropped() throws {
        let json = #"{"app":"coach","version":4,"aiSettings":{},"deletedIds":[],"health":[],"sessions":[{"id":"ok","date":"2026-08-04","plan":{"sessionType":"Push"},"log":[]},{"no":"date"}],"events":[]}"#
        let b = try decode(Backup.self, json)
        XCTAssertEqual(b.sessions.count, 1)
        XCTAssertEqual(b.unparsed.sessions.count, 1)
        let out = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as! [String: Any]
        XCTAssertEqual((out["sessions"] as! [Any]).count, 2)
    }
}

