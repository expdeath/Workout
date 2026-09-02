import XCTest
@testable import CoachApp

/// sanitizePlan() is the deterministic safety net on top of whatever the
/// model returns — it must never let a suggested weight jump further
/// than a plausible plate step past the athlete's own logged history,
/// regardless of what the AI proposes. These pin that behavior down.
final class GeminiClientTests: XCTestCase {

    private func session(exerciseName: String, weight: String, reps: String, date: String) -> Session {
        let plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: exerciseName, sets: 3, reps: "8-10")], estTimeMin: 45)
        return Session(id: "\(date)#1", date: date, startedAt: 0, checkin: nil, plan: plan, log: [[SetLog(weight: weight, reps: reps, done: true)]], finished: true)
    }

    func testSanitizePlan_capsSuggestedWeightThatJumpsTooFar() {
        let history = [session(exerciseName: "Bench Press", weight: "60", reps: "10", date: "2026-01-01")]
        // last logged was 60kg; model suggests a wild 120kg jump
        let plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 3, reps: "8-10", suggestedWeight: "120kg")], estTimeMin: 45)
        let checkin = Checkin(timeAvail: "60")

        let out = Gemini.sanitizePlan(plan, history, checkin)
        // cap = min(max(60*1.15, 60+2.5), 200) = min(69, 200) = 69, rounded to nearest 2.5 -> 70
        XCTAssertEqual(out.exercises.first?.suggestedWeight, "70kg")
    }

    func testSanitizePlan_leavesReasonableSuggestionUntouched() {
        let history = [session(exerciseName: "Bench Press", weight: "60", reps: "10", date: "2026-01-01")]
        let plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 3, reps: "8-10", suggestedWeight: "62.5kg")], estTimeMin: 45)
        let out = Gemini.sanitizePlan(plan, history, Checkin(timeAvail: "60"))
        XCTAssertEqual(out.exercises.first?.suggestedWeight, "62.5kg")
    }

    func testSanitizePlan_noHistoryAllowsAnyReasonableWeight() {
        // First-ever exercise: no lastPerformance to anchor against, so
        // only the absolute 200kg ceiling applies.
        let plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench Press", sets: 3, reps: "8-10", suggestedWeight: "40kg")], estTimeMin: 45)
        let out = Gemini.sanitizePlan(plan, [], Checkin(timeAvail: "60"))
        XCTAssertEqual(out.exercises.first?.suggestedWeight, "40kg")
    }

    func testSanitizePlan_capsExerciseCountAtSix() {
        let exercises = (1...9).map { Plan.Exercise(name: "Exercise \($0)", sets: 3, reps: "10") }
        let plan = Plan(sessionType: "Push", exercises: exercises, estTimeMin: 45)
        let out = Gemini.sanitizePlan(plan, [], Checkin(timeAvail: "60"))
        XCTAssertEqual(out.exercises.count, 6)
    }

    func testSanitizePlan_capsEstTimeMinToCheckinBudget() {
        let plan = Plan(sessionType: "Push", exercises: [Plan.Exercise(name: "Bench", sets: 3, reps: "10")], estTimeMin: 500)
        let out = Gemini.sanitizePlan(plan, [], Checkin(timeAvail: "45"))
        // avail(45) + 24 walking = 69
        XCTAssertEqual(out.estTimeMin, 69)
    }

    // MARK: buildUserMessage — smoke tests, must not crash on edge inputs

    func testBuildUserMessage_emptyHistoryDoesNotCrash() {
        let msg = Gemini.buildUserMessage(Checkin(), [], [])
        XCTAssertTrue(msg.contains("No logged sessions yet"))
    }

    func testBuildUserMessage_includesSessionPreferenceWish() {
        var ci = Checkin()
        ci.wish = "cardio"
        let msg = Gemini.buildUserMessage(ci, [], [])
        XCTAssertTrue(msg.contains("CARDIO day"))
    }
}
