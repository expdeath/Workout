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
        case "history": return .history
        case "records": return .records
        case "progress": return .progress
        case "settings": return .settings
        case "workouts": return .workouts
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
        // `COACH_DEBUG_WORKOUTS=1`: a trainer's workout scheduled today + a daily add-on
        if ProcessInfo.processInfo.environment["COACH_DEBUG_WORKOUTS"] == "1" {
            let wd = Calendar.current.component(.weekday, from: Date()) - 1
            Workouts.save(SavedWorkout(name: "Upper A", source: "trainer", trainer: "Sam", days: [wd, (wd + 2) % 7], exercises: [
                .init(name: "Flat Dumbbell Press", sets: 4, reps: "6-8"),
                .init(name: "Barbell Row", sets: 3, reps: "8", weight: "60kg", rest: "2 min"),
                .init(name: "Lateral Raise", sets: 3, reps: "12-15", rest: "60s"),
            ]))
            Workouts.save(SavedWorkout(name: "Lower B", source: "trainer", trainer: "Sam", adapt: true, days: [(wd + 1) % 7], exercises: [
                .init(name: "Back Squat", sets: 4, reps: "6", weight: "85kg", rest: "3 min"),
                .init(name: "Romanian Deadlift", sets: 3, reps: "8"),
            ]))
            Workouts.save(SavedWorkout(name: "Daily core", kind: "addon", exercises: [
                .init(name: "Plank", sets: 3, reps: "45s", rest: "30s"), .init(name: "Dead Bug", sets: 2, reps: "10"),
            ]))
        }
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
        if ProcessInfo.processInfo.environment["COACH_DEBUG_RICH"] == "1" { seedRich() }
    }

    /// `COACH_DEBUG_RICH=1`: eight weeks of push/pull/legs + walks with
    /// slowly rising weights and daily Watch rows — enough for every
    /// dashboard card to have something to show in screenshots. (The UI
    /// tests use the plain seed above.)
    private static func seedRich() {
        let days: [(Int, String)] = (1...56).compactMap { d in
            let dow = d % 7
            return dow == 1 || dow == 3 || dow == 5 ? (d, ["Push", "Pull", "Legs"][(d / 2) % 3]) : (dow == 6 ? (d, "Cardio") : nil)
        }
        let lifts: [String: [(String, Double)]] = [
            "Push": [("Flat Dumbbell Press", 20), ("Incline Machine Press", 30), ("Cable Triceps Pushdown", 18)],
            "Pull": [("Chest Supported Row", 36), ("Lat Pulldown", 50), ("Cable Curl", 14)],
            "Legs": [("Leg Press", 90), ("Romanian Deadlift", 40), ("Leg Curl", 30)],
        ]
        for (d, type) in days {
            let date = Helpers.daysAgoStr(d)
            let progress = Double(56 - d) / 56
            if type == "Cardio" {
                let km = String(format: "%.1f", 3 + progress * 2)
                let plan = Plan(sessionType: "Cardio", title: "Outdoor walk", exercises: [Plan.Exercise(name: "Outdoor Walk", sets: 1, reps: "40min")])
                LocalStore.shared.seed(session: Session(id: "\(date)#9", date: date, startedAt: 0, checkin: nil, plan: plan,
                                                        log: [[SetLog(done: true, time: "45", dist: km)]], finished: true,
                                                        fin: FinishInfo(rpe: 4), durationMin: 45))
                continue
            }
            let exs = lifts[type] ?? []
            let plan = Plan(sessionType: type, title: "", exercises: exs.map { Plan.Exercise(name: $0.0, sets: 3, reps: "8-12", rpe: "8") })
            let log = exs.map { ex in
                let w = Helpers.fmtKg(((ex.1 * (1 + 0.5 * progress)) / 2.5).rounded() * 2.5)
                return (0..<3).map { i in SetLog(weight: w, reps: "\(12 - i)", done: true) }
            }
            LocalStore.shared.seed(session: Session(id: "\(date)#1", date: date, startedAt: 0, checkin: nil, plan: plan, log: log,
                                                    finished: true, fin: FinishInfo(rpe: 7), durationMin: 60 + d % 4 * 5))
        }
        for d in 1...30 {
            let wave = sin(Double(d) / 3)
            LocalStore.shared.mergeHealth(HealthRow(date: Helpers.daysAgoStr(d), hrv: 48 + 6 * wave, rhr: 58 - 2 * wave,
                                                    sleepH: 7 + 0.6 * wave, weightKg: 78 - Double(30 - d) * 0.05))
        }
        LocalStore.shared.mergeHealth(HealthRow(date: Helpers.todayStr(), hrv: 56, rhr: 55, sleepH: 7.6))
    }
}
#endif
