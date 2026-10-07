#if DEBUG
import Foundation

/// Simulator-only seeding for screenshot/UI verification without a real
/// Google sign-in. Runs fully offline (Cloud.offline — nothing reaches
/// Firestore) with a fake account. Triggered by an env var set via
/// `SIMCTL_CHILD_COACH_DEBUG_SEED=1 xcrun simctl launch …`.
/// Compiled out of every non-Debug build.
enum DebugSeed {
    /// `COACH_DEBUG_SCREEN=checkIn|generating` boots straight onto that
    /// screen, for screenshotting screens deeper than Home.
    static var startScreen: Screen? {
        switch ProcessInfo.processInfo.environment["COACH_DEBUG_SCREEN"] {
        case "checkIn": return .checkIn
        case "generating": return .generating
        case "workout": return .workout
        case "finish": return .finish
        default: return nil
        }
    }

    static func applyIfRequested() {
        guard ProcessInfo.processInfo.environment["COACH_DEBUG_SEED"] == "1" else { return }
        Account.wipeLocal()
        Cloud.shared.debugActivate(
            account: Cloud.AccountInfo(accountId: "preview", name: "Preview", admin: false, email: "preview@example.invalid"),
            geminiKey: "debug-not-a-real-key"
        )

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
        LocalStore.shared.seed(session: yesterday)
        // an in-progress session for the Workout/Finish screens: every
        // logging mode (strength, a superset pair, cardio, tick-off)
        if startScreen == .workout || startScreen == .finish {
            let today = Plan(
                sessionType: "Push", title: "Chest & shoulders", recoveryScore: 74,
                reasoning: "Good sleep, low soreness — a full push day.",
                warmup: ["5min row easy"],
                exercises: [
                    Plan.Exercise(name: "Flat Dumbbell Press", sets: 2, reps: "8-12", rpe: "8", rest: "90s", notes: "Control the eccentric.", alt: "Machine Chest Press", suggestedWeight: "24kg"),
                    Plan.Exercise(name: "Lateral Raise", sets: 2, reps: "12-15", rpe: "8", rest: "60s", superset: "A"),
                    Plan.Exercise(name: "Cable Triceps Pushdown", sets: 2, reps: "12", rpe: "8", rest: "60s", superset: "A"),
                    Plan.Exercise(name: "Incline Walk", sets: 1, reps: "10min", rpe: "6", rest: "0s"),
                    Plan.Exercise(name: "Doorway Chest Stretch", sets: 1, reps: "30s each side", rpe: "", rest: "0s"),
                ],
                cooldown: ["easy breathing 1min"], estTimeMin: 55, concerns: ""
            )
            let t = Session(
                id: "\(Helpers.todayStr())#1", date: Helpers.todayStr(), startedAt: Date().timeIntervalSince1970 * 1000 - 40 * 60000,
                checkin: Checkin(), plan: today,
                log: today.exercises.map { Array(repeating: SetLog(), count: $0.sets) }
            )
            Cloud.shared.setState("today", try? JSONValue.encoding(t))
        }
        // today's Watch row → check-in shows "Watch data loaded" with details open
        LocalStore.shared.mergeHealth(HealthRow(date: Helpers.todayStr(), hrv: 52, rhr: 57, raw: "Sleep 7h10m · HRV 52 · RHR 57 · Steps 8400"))
    }
}
#endif
