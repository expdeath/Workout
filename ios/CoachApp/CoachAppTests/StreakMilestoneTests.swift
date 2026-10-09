import XCTest
@testable import CoachApp

/// The streak milestones count against your own weekly target — the same
/// number the streak stat shows (they used to assume 3 a week).
@MainActor
final class StreakMilestoneTests: XCTestCase {
    override func setUp() { Cloud.shared.offline = true }

    /// 3 sessions in each of the last 12 full weeks.
    private func history() -> [Session] {
        let cal = Calendar.current
        let thisMonday = Helpers.noonDate(Stats.mondayOf(Helpers.todayStr()))!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return (1...12).flatMap { w -> [Session] in
            (0..<3).map { d in
                let day = cal.date(byAdding: .day, value: -7 * w + d, to: thisMonday)!
                let iso = fmt.string(from: day)
                return Session(id: "\(iso)#\(d)", date: iso, startedAt: 0, checkin: nil,
                               plan: Plan(sessionType: "Push", exercises: [.init(name: "Bench Press", sets: 1, reps: "5")]),
                               log: [[SetLog(weight: "60", reps: "5", done: true)]], finished: true)
            }
        }
    }

    private func streakMilestone(target: Int) -> Int {
        LocalStore.shared.updateAISettings { $0.weeklyTarget = target }
        return Dashboard.ladders(history()).first { $0.key == "streak" }!.value
    }

    func testStreakMilestonesUseYourTarget() {
        let h = history()
        XCTAssertEqual(streakMilestone(target: 3), Stats.weekStats(h, target: 3).streak)
        XCTAssertEqual(streakMilestone(target: 4), Stats.weekStats(h, target: 4).streak, "same number as the streak stat")
        XCTAssertGreaterThan(streakMilestone(target: 3), streakMilestone(target: 4), "3 a week meets a target of 3, not 4")
    }
}
