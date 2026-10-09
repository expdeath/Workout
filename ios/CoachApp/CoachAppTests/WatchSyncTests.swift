import XCTest
@testable import CoachApp

/// The iPhone half of the Watch app: what it shows the Watch, and that a
/// command from the wrist becomes the same edit a tap on the phone makes —
/// the same checks as the Android app's WatchSyncTest.
@MainActor
final class WatchSyncTests: XCTestCase {
    private final class Fake: WatchTarget {
        var todayPlan: Session?
        var history: [Session] = []
        var rest: AppState.RestTimer?
        var calls: [String] = []

        init(_ t: Session?, history: [Session] = [], rest: AppState.RestTimer? = nil) { todayPlan = t; self.history = history; self.rest = rest }

        private func s(_ v: String?) -> String { v ?? "nil" }
        private func b(_ v: Bool?) -> String { v.map { "\($0)" } ?? "nil" }
        func updateSet(_ exI: Int, _ setI: Int, weight: String?, reps: String?, time: String?, dist: String?, done: Bool?, effort: String?) {
            calls.append("set \(exI)/\(setI) w=\(s(weight)) r=\(s(reps)) t=\(s(time)) d=\(s(dist)) done=\(b(done)) e=\(s(effort))")
        }
        func addSet(_ exI: Int) { calls.append("addSet \(exI)") }
        func startRest(seconds: Double, exName: String, startedAt: Date) {
            calls.append("rest \(Int(seconds)) \(exName) @\(Int(startedAt.timeIntervalSince1970 * 1000))")
        }
        func extendRest(seconds: Int) { calls.append("extend \(seconds)") }
        func stopRest() { calls.append("stopRest") }
        func finish(rpe: Int) { calls.append("finish \(rpe)") }
    }

    private let plan = Plan(sessionType: "Push", title: "Push — strength", exercises: [
        Plan.Exercise(name: "Bench Press", sets: 3, reps: "6-8", rest: "2min", suggestedWeight: "60kg"),
        Plan.Exercise(name: "Plank", sets: 2, reps: "45s", rest: "45s"),
    ])
    private var today: Session {
        Session(id: "2026-10-10#1000", date: "2026-10-10", startedAt: 1000, checkin: nil, plan: plan,
                log: [[SetLog(weight: "60", reps: "8", done: true, effort: "good"), SetLog(), SetLog()], [SetLog(), SetLog()]])
    }
    // last time: every set at the top of 6-8 → +2.5 kg today
    private let lastWeek = Session(id: "2026-10-03#1", date: "2026-10-03", startedAt: 1, checkin: nil,
                                   plan: Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 2, reps: "6-8")]),
                                   log: [[SetLog(weight: "60", reps: "8", done: true), SetLog(weight: "60", reps: "8", done: true)]], finished: true)

    private func cmd(_ c: String, ex: Int = 0, name: String = "Bench Press", set: Int = 1, id: String? = nil, session: String? = nil) -> WatchCommand {
        WatchCommand(id: id ?? c, at: 5_000, cmd: c, session: session ?? today.id, ex: ex, name: name, set: set)
    }

    override func setUp() {
        Cloud.shared.offline = true
        LocalStore.shared.wipe()
        WatchSync.shared.reset()
    }

    func testSnapshotShowsTodaysWorkoutWithThePhonesHints() {
        let rest = AppState.RestTimer(endsAt: Date(timeIntervalSince1970: 9), total: 120, exName: "Bench Press")
        let s = WatchSync.shared.snapshot(Fake(today, history: [lastWeek], rest: rest))
        XCTAssertTrue(s.active)
        XCTAssertEqual(s.id, today.id)
        XCTAssertEqual(s.startedAt, 1000)
        let bench = s.exercises[0]
        XCTAssertEqual(bench.mode, Stats.logMode("Bench Press", "Push"))
        XCTAssertEqual(bench.restSec, 120)
        XCTAssertEqual(bench.target, "62.5")
        XCTAssertEqual(bench.last, "60kg×8, 60kg×8")
        XCTAssertEqual(bench.sets.map(\.done), [true, false, false])
        XCTAssertEqual(bench.sets[0].e, "good")
        XCTAssertEqual(bench.sets[1].pw, "62.5")
        XCTAssertEqual(bench.sets[1].pr, "8")
        XCTAssertEqual(s.exercises[1].mode, "check") // planks get ticked, not weighed
        XCTAssertEqual(s.rest, WRest(endsAt: 9_000, total: 120, ex: "Bench Press"))
        XCTAssertEqual(s.doneSets, 1)
        XCTAssertEqual(s.totalSets, 5)
    }

    func testNoWorkoutAndFinishedWorkoutSnapshots() {
        XCTAssertFalse(WatchSync.shared.snapshot(Fake(nil)).active)
        var t = today
        t.finished = true
        let done = WatchSync.shared.snapshot(Fake(t))
        XCTAssertFalse(done.active)
        XCTAssertTrue(done.finished)
    }

    func testASetLoggedOnTheWatchIsSavedAndStartsRestFromTheWrist() {
        let app = Fake(today)
        var c = cmd(WatchCommand.logSet)
        c.w = "62.5"; c.r = "7"
        WatchSync.shared.handle(app, c, now: Date(timeIntervalSince1970: 6))
        XCTAssertEqual(app.calls, ["set 0/1 w=62.5 r=7 t=nil d=nil done=true e=nil", "rest 120 Bench Press @5000"])
    }

    func testEachCommandIsAppliedOnceAndAcked() {
        let app = Fake(today)
        var c = cmd(WatchCommand.effort, id: "c1")
        c.effort = "easy"
        WatchSync.shared.handle(app, c)
        WatchSync.shared.handle(app, c) // redelivered
        XCTAssertEqual(app.calls.count, 1)
        XCTAssertTrue(WatchSync.shared.snapshot(app).acks.contains("c1"))
    }

    func testCommandsForAnOldSessionAreIgnored() {
        let app = Fake(today)
        WatchSync.shared.handle(app, cmd(WatchCommand.logSet, session: "2026-10-09#5"))
        WatchSync.shared.handle(app, cmd(WatchCommand.restSkip, id: "x", session: "2026-10-09#5"))
        XCTAssertTrue(app.calls.isEmpty)
    }

    func testTheExerciseIsFoundByNameAfterThePlanChanged() {
        var t = today
        t.plan.exercises = [plan.exercises[1]]
        t.log = [today.log[1]]
        let app = Fake(t)
        WatchSync.shared.handle(app, cmd(WatchCommand.logSet, ex: 1, name: "Plank", set: 0))
        XCTAssertEqual(app.calls.first, "set 0/0 w=nil r=nil t=nil d=nil done=true e=nil")
    }

    func testBadEffortsAreRefusedAndRpeIsClamped() {
        let app = Fake(today)
        var e = cmd(WatchCommand.effort, id: "e")
        e.effort = "<script>"
        var f = cmd(WatchCommand.finish, id: "f")
        f.rpe = 42
        WatchSync.shared.handle(app, e)
        WatchSync.shared.handle(app, f)
        XCTAssertEqual(app.calls, ["finish 7"])
    }

    func testRestAndSetEditsMapToTheSameAppStateCalls() {
        let app = Fake(today)
        var add = cmd(WatchCommand.restAdd, id: "1")
        add.sec = 15
        WatchSync.shared.handle(app, add)
        WatchSync.shared.handle(app, cmd(WatchCommand.restSkip, id: "2"))
        WatchSync.shared.handle(app, cmd(WatchCommand.addSet, id: "3"))
        WatchSync.shared.handle(app, cmd(WatchCommand.undoSet, set: 0, id: "4"))
        XCTAssertEqual(app.calls, ["extend 15", "stopRest", "addSet 0", "set 0/0 w=nil r=nil t=nil d=nil done=false e=nil"])
    }
}
