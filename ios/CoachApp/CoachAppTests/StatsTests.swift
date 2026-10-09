import XCTest
@testable import CoachApp

/// The regex-based health-text parser and the effort/rep-range
/// progression logic are the highest-risk parts of the stats.js port —
/// hand-translated regexes are exactly where a subtle JS→Swift mistake
/// hides. These check against real Watch-shortcut-shaped payloads.
final class StatsTests: XCTestCase {

    // MARK: parseHealthNumbers

    func testParseHealthNumbers_shortcutLabelFormat() {
        let n = Stats.parseHealthNumbers("HRV: 48.2 RHR: 57 SleepHrs: 7.5 Steps: 8,432")
        XCTAssertEqual(n.hrv, 48.2)
        XCTAssertEqual(n.rhr, 57)
        XCTAssertEqual(n.sleepH, 7.5)
        XCTAssertEqual(n.steps, 8432)
    }

    func testParseHealthNumbers_sleepHrsInSeconds_dedupesDoubleCount() {
        // Watch + iPhone both log the same night; raw seconds sum can
        // double it — dedupe kicks in above 11h.
        let n = Stats.parseHealthNumbers("SleepHrs: 54000") // 15h raw -> /2 = 7.5h
        XCTAssertEqual(n.sleepH, 7.5)
    }

    func testParseHealthNumbers_freeformSleepFallback() {
        let n = Stats.parseHealthNumbers("slept 6.5 hours last night, felt okay")
        XCTAssertEqual(n.sleepH, 6.5)
    }

    func testParseHealthNumbers_freeformSleepColonFormat() {
        // JS rounds sleepH to 1 decimal (Math.round(x*10)/10), so
        // 7 + 20/60 = 7.333... rounds to 7.3, not 7.33.
        let n = Stats.parseHealthNumbers("sleep: 7:20")
        XCTAssertEqual(n.sleepH, 7.3)
    }

    func testParseHealthNumbers_spo2FractionVsPercent() {
        let frac = Stats.parseHealthNumbers("SpO2: 0.96")
        XCTAssertEqual(frac.spo2, 96)
        let pct = Stats.parseHealthNumbers("SpO2: 96")
        XCTAssertEqual(pct.spo2, 96)
    }

    func testParseHealthNumbers_vo2maxOutOfClampRangeIsDropped() {
        let n = Stats.parseHealthNumbers("VO2Max: 200") // implausible, clamp [10,90]
        XCTAssertNil(n.vo2max)
    }

    func testParseHealthNumbers_emptyStringReturnsAllNil() {
        let n = Stats.parseHealthNumbers("")
        XCTAssertNil(n.hrv)
        XCTAssertNil(n.rhr)
        XCTAssertNil(n.sleepH)
    }

    // MARK: suggestNextWeight

    func testSuggestNextWeight_allSetsToppedOut_suggestsPlus2point5() {
        let lp = Stats.LastPerformance(date: "2026-01-01", sets: [
            SetLog(weight: "60", reps: "12", done: true),
            SetLog(weight: "60", reps: "12", done: true),
        ], repsRange: "10-12")
        XCTAssertEqual(Stats.suggestNextWeight(lp, "10-12"), 62.5)
    }

    func testSuggestNextWeight_allSetsEasy_suggestsPlus5() {
        let lp = Stats.LastPerformance(date: "2026-01-01", sets: [
            SetLog(weight: "60", reps: "12", done: true, effort: "easy"),
            SetLog(weight: "60", reps: "12", done: true, effort: "easy"),
        ], repsRange: "10-12")
        XCTAssertEqual(Stats.suggestNextWeight(lp, "10-12"), 65)
    }

    func testSuggestNextWeight_anyGrindSet_holdsWeight() {
        let lp = Stats.LastPerformance(date: "2026-01-01", sets: [
            SetLog(weight: "60", reps: "12", done: true, effort: "grind"),
            SetLog(weight: "60", reps: "12", done: true),
        ], repsRange: "10-12")
        XCTAssertNil(Stats.suggestNextWeight(lp, "10-12"))
    }

    func testSuggestNextWeight_notAllToppedOut_holdsWeight() {
        let lp = Stats.LastPerformance(date: "2026-01-01", sets: [
            SetLog(weight: "60", reps: "9", done: true),
        ], repsRange: "10-12")
        XCTAssertNil(Stats.suggestNextWeight(lp, "10-12"))
    }

    // MARK: muscleGroupOf — order-sensitive classifier

    func testMuscleGroupOf_legPressBeforeGenericPress() {
        // "leg press" must hit Legs, not fall through to Chest's generic "press".
        XCTAssertEqual(Stats.muscleGroupOf("Leg Press"), "Legs")
    }

    func testMuscleGroupOf_legRaiseIsCoreNotLegs() {
        XCTAssertEqual(Stats.muscleGroupOf("Hanging Leg Raise"), "Core")
    }

    func testMuscleGroupOf_hikeIsCardio() {
        XCTAssertEqual(Stats.muscleGroupOf("Hike"), "Cardio")
    }

    func testMuscleGroupOf_unknownIsOther() {
        XCTAssertEqual(Stats.muscleGroupOf("Juggling"), "Other")
    }

    // MARK: epley1RM

    func testEpley1RM_oneRepReturnsWeightItself() {
        XCTAssertEqual(Stats.epley1RM("100", "1"), 100)
    }

    func testEpley1RM_invalidInputsReturnNil() {
        XCTAssertNil(Stats.epley1RM("", "8"))
        XCTAssertNil(Stats.epley1RM("60", ""))
        XCTAssertNil(Stats.epley1RM("0", "8"))
    }

    // MARK: detectPRs

    func testDetectPRs_newWeightBeatsOldRecord() {
        var plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 3, reps: "8-10")], estTimeMin: 45)
        var prior = Session(id: "p1", date: "2026-01-01", startedAt: 0, checkin: nil, plan: plan, log: [[SetLog(weight: "60", reps: "8", done: true)]], finished: true)
        plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 3, reps: "8-10")], estTimeMin: 45)
        let today = Session(id: "t1", date: "2026-01-08", startedAt: 0, checkin: nil, plan: plan, log: [[SetLog(weight: "65", reps: "8", done: true)]], finished: true)

        let prs = Stats.detectPRs(today, [prior])
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.kind, "weight")
        XCTAssertEqual(prs.first?.from, 60)
        XCTAssertEqual(prs.first?.to, 65)
    }

    func testDetectPRs_firstTimeExerciseIsNotAPR() {
        let plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 3, reps: "8-10")], estTimeMin: 45)
        let today = Session(id: "t1", date: "2026-01-08", startedAt: 0, checkin: nil, plan: plan, log: [[SetLog(weight: "65", reps: "8", done: true)]], finished: true)
        XCTAssertTrue(Stats.detectPRs(today, []).isEmpty)
    }
}
