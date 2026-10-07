import XCTest
@testable import CoachApp

/// The HealthKit reader's pure parts: sleep de-duplication and the
/// Shortcut-format text both apps parse.
final class HealthKitSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func iv(_ fromH: Double, _ toH: Double) -> DateInterval {
        DateInterval(start: t0.addingTimeInterval(fromH * 3600), end: t0.addingTimeInterval(toH * 3600))
    }

    func testOverlappingSleepFromWatchAndPhoneCountsOnce() {
        // Watch 23:00–07:00 and iPhone 23:30–06:30 for the same night = 8h, not 15h
        XCTAssertEqual(HealthKitSync.mergedDuration([iv(0, 8), iv(0.5, 7.5)]) / 3600, 8, accuracy: 0.001)
        // a gap (woke 03:00–03:30) is not counted
        XCTAssertEqual(HealthKitSync.mergedDuration([iv(0, 4), iv(4.5, 8)]) / 3600, 7.5, accuracy: 0.001)
        XCTAssertEqual(HealthKitSync.mergedDuration([]), 0)
    }

    func testShortcutTextParsesBackToTheSameNumbers() {
        let m = HealthKitSync.DayMetrics(hrv: 51.8, rhr: 67.3, steps: 19712, sleepH: 7.25, vo2max: 33.6,
                                         kcal: 967, exerciseMin: 87, distKm: 13.58, respRate: 18.4, wristC: 35.87)
        let n = Stats.parseHealthNumbers(m.shortcutText)
        XCTAssertEqual(n.hrv, 51.8)
        XCTAssertEqual(n.rhr, 67.3)
        XCTAssertEqual(n.steps, 19712)
        XCTAssertEqual(n.sleepH, 7.3, "parser rounds sleep to 0.1h")
        XCTAssertEqual(n.vo2max, 33.6)
        XCTAssertEqual(n.kcal, 967)
        XCTAssertEqual(n.exerciseMin, 87)
        XCTAssertEqual(n.distKm, 13.58)
        XCTAssertEqual(n.respRate, 18.4)
        XCTAssertEqual(n.wristC, 35.87)
    }

    func testMissingMetricsAreLeftOutNotMisread() {
        // the Shortcut's old "ExerciseMin: DistanceKm: 1.54" bug: an empty
        // label must not make the parser read the next number
        let m = HealthKitSync.DayMetrics(hrv: 40, distKm: 1.54)
        XCTAssertFalse(m.shortcutText.contains("ExerciseMin"))
        XCTAssertNil(Stats.parseHealthNumbers(m.shortcutText).exerciseMin)
        XCTAssertTrue(HealthKitSync.DayMetrics().isEmpty)
    }
}
