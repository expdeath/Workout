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
}
