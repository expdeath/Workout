#if DEBUG
import Foundation

/// Simulator-only seeding for screenshot/UI verification without typing
/// a real invite code through UI automation. Triggered by an env var
/// set via `SIMCTL_CHILD_COACH_DEBUG_SEED=1 xcrun simctl launch …`.
/// Compiled out of every non-Debug build.
enum DebugSeed {
    static func applyIfRequested() {
        guard ProcessInfo.processInfo.environment["COACH_DEBUG_SEED"] == "1" else { return }
        Account.wipeLocal()
        Account.apply(InviteCode(name: "Preview", repo: "example/coach-data-preview", ghToken: "debug-not-a-real-token", geminiKey: "debug-not-a-real-key"))

        let plan = Plan(
            sessionType: "Push", title: "Push Day", recoveryScore: 78,
            reasoning: "Solid recovery, ready to push volume.",
            warmup: ["10min bike easy"],
            exercises: [
                Plan.Exercise(name: "Flat Dumbbell Press", sets: 3, reps: "10-12", rpe: "7-8", rest: "90s", suggestedWeight: "24kg"),
                Plan.Exercise(name: "Incline Machine Press", sets: 3, reps: "10-12", rpe: "7-8", rest: "90s"),
            ],
            cooldown: ["doorway chest stretch"], estTimeMin: 52, concerns: ""
        )
        var yesterday = Session(
            id: "2026-08-30#1", date: "2026-08-30", startedAt: 0, checkin: nil, plan: plan,
            log: [[SetLog(weight: "24", reps: "11", done: true)], [SetLog(weight: "20", reps: "12", done: true)]],
            finished: true, fin: FinishInfo(rpe: 7, pain: "", feedback: "Felt strong")
        )
        yesterday.debrief = "Good pressing volume today — chest and shoulders both moved well. Next time, add a set to incline press since reps were easy across the board."
        LocalStore.shared.upsert(session: yesterday)
    }
}
#endif
