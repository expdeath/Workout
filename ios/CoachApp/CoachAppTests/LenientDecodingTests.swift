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
        XCTAssertThrowsError(try decode(Plan.self, #"{"sessionType":"Push","exercises":[],"estTimeMin":50}"#))
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
}
