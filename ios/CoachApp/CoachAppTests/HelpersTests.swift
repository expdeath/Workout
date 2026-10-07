import XCTest
@testable import CoachApp

/// Mirrors quickReadiness()/daysAgoStr() in src/utils/helpers.js.
final class HelpersTests: XCTestCase {
    func testQuickReadinessNormalDay() {
        // 50 + (7-5)*5 + OK 5 + no soreness 10
        XCTAssertEqual(Helpers.quickReadiness(Checkin()), 75)
    }

    func testQuickReadinessClampsLow() {
        let c = Checkin(energy: 3, sleep: "Poor", soreness: "Very sore", backTight: true)
        XCTAssertEqual(Helpers.quickReadiness(c), 5)
    }

    func testQuickReadinessClampsHigh() {
        let c = Checkin(energy: 10, sleep: "Great", soreness: "None")
        XCTAssertEqual(Helpers.quickReadiness(c), 98)
    }

    func testDaysAgoStr() {
        XCTAssertEqual(Helpers.daysAgoStr(0), Helpers.todayStr())
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let today = f.date(from: Helpers.todayStr())!
        let yday = f.date(from: Helpers.daysAgoStr(1))!
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: yday, to: today).day, 1)
    }

    // ── Plate math + rest parsing (same answers as src/utils/helpers.js
    //    plateBreakdown/parsePlates and Workout.jsx parseRestSeconds) ──

    func testPlateBreakdownGreedyPerSide() {
        let b = Helpers.plateBreakdown(25)!
        XCTAssertEqual(b.perSide, [2.5])
        XCTAssertTrue(b.exact)
        let c = Helpers.plateBreakdown(101, barKg: 20, plates: [20, 10, 5, 2.5])!
        XCTAssertEqual(c.perSide, [20, 20])
        XCTAssertEqual(c.loaded, 100)
        XCTAssertFalse(c.exact)
        XCTAssertEqual(Helpers.plateBreakdown(15)?.perSide, [], "lighter than the bar → bar only")
        XCTAssertNil(Helpers.plateBreakdown(0))
    }

    func testParsePlatesDedupesAndSorts() {
        XCTAssertEqual(Helpers.parsePlates("2.5, 25 20,20  60"), [25, 20, 2.5])
        XCTAssertNil(Helpers.parsePlates("none"))
    }

    func testParseRestSeconds() {
        XCTAssertEqual(WorkoutView.parseRestSeconds("90s"), 90)
        XCTAssertEqual(WorkoutView.parseRestSeconds("2min"), 120)
        XCTAssertEqual(WorkoutView.parseRestSeconds("1-2min"), 120)
        XCTAssertEqual(WorkoutView.parseRestSeconds(""), 90)
        XCTAssertEqual(WorkoutView.parseRestSeconds("5s"), 15, "clamped to ≥15s")
    }
}

