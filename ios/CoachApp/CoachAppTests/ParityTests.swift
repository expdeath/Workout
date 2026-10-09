import XCTest
@testable import CoachApp

/// Behaviour the web app has that the native apps must match
/// (src/utils/healthIngest.js, src/utils/workouts.js) — the same checks
/// as the Android app's ParityTest.
@MainActor
final class ParityTests: XCTestCase {
    override func setUp() {
        Cloud.shared.offline = true
        LocalStore.shared.wipe()
    }

    func testPastedHealthTextFillsTodaysNumbers() {
        HealthIngest.storeToday("  HRV: 48 RHR: 57 SleepHrs: 7.5 Steps: 8,432  ")
        let row = LocalStore.shared.backup.health.first { $0.date == Helpers.todayStr() }
        XCTAssertEqual(row?.hrv, 48)
        XCTAssertEqual(row?.rhr, 57)
        XCTAssertEqual(row?.sleepH, 7.5)
        XCTAssertEqual(row?.steps, 8432)
        XCTAssertEqual(HealthIngest.todaysText(), "HRV: 48 RHR: 57 SleepHrs: 7.5 Steps: 8,432")
    }

    func testTextWithoutNumbersPrefillsButWritesNoRow() {
        HealthIngest.storeToday("felt great, slept well")
        XCTAssertTrue(LocalStore.shared.backup.health.isEmpty)
        XCTAssertEqual(HealthIngest.todaysText(), "felt great, slept well")
    }

    func testClipboardHeuristicMatchesTheWeb() {
        XCTAssertTrue(HealthIngest.looksLikeHealthData("HRV 52 · RHR 57 · Steps 8400"))
        XCTAssertFalse(HealthIngest.looksLikeHealthData("buy milk"))
        XCTAssertFalse(HealthIngest.looksLikeHealthData("sleep well"))
        XCTAssertFalse(HealthIngest.looksLikeHealthData(String(repeating: "HRV 5", count: 200)))
    }

    func testReparseFillsMissingFieldsAndRepairsDoubledSleep() {
        LocalStore.shared.mergeHealth(HealthRow(date: "2026-09-01", raw: "HRV: 50 RHR: 60"))
        LocalStore.shared.mergeHealth(HealthRow(date: "2026-09-02", sleepH: 15, raw: "SleepHrs: 54000"))
        HealthIngest.reparseRows()
        let h = Dictionary(uniqueKeysWithValues: LocalStore.shared.backup.health.map { ($0.date, $0) })
        XCTAssertEqual(h["2026-09-01"]?.hrv, 50)
        XCTAssertEqual(h["2026-09-01"]?.rhr, 60)
        XCTAssertEqual(h["2026-09-02"]?.sleepH, 7.5, "doubled sleep repaired")
    }

    func testSavedWorkoutPlansRecordWhereTheyCameFrom() throws {
        let w = SavedWorkout(id: "w1", name: "Upper A", source: "trainer", trainer: "Sam", adapt: true,
                             exercises: [.init(name: "Bench Press", sets: 2, reps: "6")])
        let p = Workouts.templateToPlan(w, [])
        XCTAssertEqual(p.fromWorkout, .object(["id": .string("w1"), "name": .string("Upper A"), "source": .string("trainer"),
                                               "trainer": .string("Sam"), "adapt": .bool(true)]))
        XCTAssertEqual(p.estTimeMin, 5, "2 sets × 2.5 min, like the web (no 30-min floor)")
        let exact = Workouts.enforceExact(Plan(sessionType: "Push"), w, [])
        if case .object(let o)? = exact.fromWorkout { XCTAssertEqual(o["adapt"], .bool(false)) } else { XCTFail() }
        let round = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(round.fromWorkout, p.fromWorkout, "round-trips through the stored session JSON")
        XCTAssertNil(try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(Plan(sessionType: "Push"))).fromWorkout)
    }

    func testEmptyWorkoutStillEstimatesThirtyMinutes() {
        XCTAssertEqual(Workouts.templateToPlan(SavedWorkout(name: "Empty"), []).estTimeMin, 30)
    }
}
