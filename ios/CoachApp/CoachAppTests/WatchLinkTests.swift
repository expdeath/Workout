import XCTest
@testable import CoachApp

/// The protocol both watches speak (docs/watch.md) — the same checks as the
/// Android app's WatchLinkTest, so the Apple Watch and a Wear OS watch read
/// and write identical JSON and make identical guesses.
final class WatchLinkTests: XCTestCase {
    private func ex(_ name: String, _ n: Int = 3, superset: String = "", rest: Int = 90, done: Int = 0) -> WExercise {
        WExercise(name: name, restSec: rest, superset: superset, sets: (0..<n).map { WSet(done: $0 < done) })
    }

    private func cmd(_ c: String, _ ex: Int = -1, _ name: String = "", _ set: Int = -1, id: String? = nil, session: String = "s1", at: Int64 = 1_000) -> WatchCommand {
        WatchCommand(id: id ?? c, at: at, cmd: c, session: session, ex: ex, name: name, set: set)
    }

    func testStateRoundTripsThroughJson() {
        let s = WatchState(
            active: true, id: "2026-10-10#1", type: "Push", title: "Push — strength", startedAt: 42,
            exercises: [WExercise(name: "Bench", mode: "strength", reps: "6-8", rpe: "8", restSec: 120, target: "62.5", last: "60kg×8", superset: "A",
                                  sets: [WSet(w: "60", r: "8", done: true, e: "good", pw: "62.5", pr: "8")])],
            rest: WRest(endsAt: 99, total: 120, ex: "Bench"), acks: ["a", "b"], sentAt: 7
        )
        XCTAssertEqual(WatchState.fromJson(s.toJson()), s)
    }

    func testCommandRoundTripsThroughJson() {
        let c = WatchCommand(id: "id1", at: 5, cmd: WatchCommand.logSet, session: "s1", ex: 2, name: "Bench", set: 1, w: "60", r: "8",
                             effort: "easy", sec: 15, rpe: 8, workout: WorkoutSummary(start: 1, end: 2, type: "Push", kcal: 210.5, avgHr: 128, maxHr: 171))
        XCTAssertEqual(WatchCommand.fromJson(c.toJson()), c)
    }

    /// What the Android watch writes, byte for byte, reads the same here.
    func testReadsTheKotlinEncoding() {
        let kotlin = #"{"v":1,"active":true,"id":"s1","type":"Push","title":"T","startedAt":1000,"exercises":[{"name":"Bench","mode":"strength","reps":"6-8","rpe":"","restSec":120,"target":"62.5","last":"","superset":"","sets":[{"w":"60","r":"8","t":"","d":"","done":true,"e":"good","pw":"","pr":"","pt":""}]}],"rest":null,"acks":["c1"],"finished":false,"sentAt":5}"#
        let s = WatchState.fromJson(kotlin)
        XCTAssertEqual(s?.exercises.first?.sets.first, WSet(w: "60", r: "8", done: true, e: "good"))
        XCTAssertNil(s?.rest)
        XCTAssertEqual(s?.acks, ["c1"])
    }

    func testBadJsonIsIgnoredNotFatal() {
        XCTAssertNil(WatchState.fromJson("not json"))
        XCTAssertNil(WatchCommand.fromJson(#"{"cmd":"logSet"}"#)) // no id
        // wrong types read as missing
        let s = WatchState.fromJson(#"{"active":"yes","exercises":[{"name":"Row","restSec":"x","sets":[{"done":1}]}]}"#)
        XCTAssertEqual(s?.active, false)
        XCTAssertEqual(s?.exercises.first?.restSec, 90)
        XCTAssertEqual(s?.exercises.first?.sets.first?.done, false)
    }

    func testNextFollowsPlanOrder() {
        let s = WatchState(exercises: [ex("A", 2, done: 2), ex("B", 3, done: 1), ex("C")])
        XCTAssertEqual(s.next(), WFocus(ex: 1, set: 1))
        XCTAssertNil(WatchState(exercises: [ex("A", 2, done: 2)]).next())
    }

    func testSupersetsAlternateRounds() {
        var s = WatchState(id: "s1", exercises: [ex("A", 2, superset: "x"), ex("B", 2, superset: "x"), ex("C", 1)])
        var order: [WFocus] = []
        while let f = s.next() {
            order.append(f)
            s = s.applying(cmd(WatchCommand.logSet, f.ex, s.exercises[f.ex].name, f.set, id: "\(f.ex)\(f.set)"))
        }
        XCTAssertEqual(order, [WFocus(ex: 0, set: 0), WFocus(ex: 1, set: 0), WFocus(ex: 0, set: 1), WFocus(ex: 1, set: 1), WFocus(ex: 2, set: 0)])
    }

    func testPrefillUsesWhatYouJustLiftedThenTheHint() {
        let e = WExercise(name: "Bench", reps: "6-8", target: "62.5", sets: [WSet(w: "60", r: "8", done: true, pw: "62.5", pr: "8"), WSet(pw: "62.5", pr: "7")])
        let s = WatchState(exercises: [e, WExercise(name: "Row", reps: "10-12", target: "40", sets: [WSet()])])
        XCTAssertEqual(s.prefill(0, 1), WPrefill(w: "60", r: "8", t: "", d: ""))
        XCTAssertEqual(s.prefill(1, 0), WPrefill(w: "40", r: "10", t: "", d: ""))
    }

    func testLoggingASetOnTheWristStartsRestFromThen() {
        var c = cmd(WatchCommand.logSet, 0, "Bench", 0, at: 10_000)
        c.w = "60"; c.r = "8"
        let s = WatchState(id: "s1", exercises: [ex("Bench", rest: 120)]).applying(c)
        XCTAssertEqual(s.exercises[0].sets[0], WSet(w: "60", r: "8", done: true))
        XCTAssertEqual(s.rest, WRest(endsAt: 130_000, total: 120, ex: "Bench"))
        var add = cmd(WatchCommand.restAdd, id: "x")
        add.sec = 15
        let more = s.applying(add)
        XCTAssertEqual(more.rest, WRest(endsAt: 145_000, total: 135, ex: "Bench"))
        XCTAssertNil(more.applying(cmd(WatchCommand.restSkip, id: "y")).rest)
    }

    func testCommandsForAnotherSessionDoNothing() {
        let s = WatchState(id: "today", exercises: [ex("Bench")])
        XCTAssertEqual(s.applying(cmd(WatchCommand.logSet, 0, "Bench", 0, session: "yesterday")), s)
    }

    func testExerciseIsFoundByNameWhenThePlanChanged() {
        let s = WatchState(id: "s1", exercises: [ex("Row"), ex("Bench")])
        let c = cmd(WatchCommand.logSet, 0, "Bench", 0)
        XCTAssertEqual(s.exerciseIndex(c), 1)
        XCTAssertTrue(s.applying(c).exercises[1].sets[0].done)
        XCTAssertNil(s.exerciseIndex(cmd(WatchCommand.logSet, 0, "Squat", 0)))
    }

    func testPendingCommandsDropOnceThePhoneAcksThem() {
        let phone = WatchState(id: "s1", exercises: [ex("Bench")])
        let c = cmd(WatchCommand.logSet, 0, "Bench", 0, id: "c1")
        XCTAssertTrue(phone.withPending([c]).exercises[0].sets[0].done)
        var answered = phone
        answered.exercises = [ex("Bench", done: 1)]
        answered.acks = ["c1"]
        XCTAssertEqual(answered.withPending([c]), answered)
    }

    func testFinishEndsTheWorkoutOnTheWatch() {
        var c = cmd(WatchCommand.finish)
        c.rpe = 8
        let s = WatchState(active: true, id: "s1", exercises: [ex("Bench")], rest: WRest(endsAt: 1, total: 1, ex: "Bench")).applying(c)
        XCTAssertFalse(s.active)
        XCTAssertTrue(s.finished)
        XCTAssertNil(s.rest)
    }
}
