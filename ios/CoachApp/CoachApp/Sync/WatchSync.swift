import Foundation
import HealthKit
import WatchConnectivity

/// What a running workout needs from the app — AppState, or a fake in tests.
@MainActor
protocol WatchTarget: AnyObject {
    var todayPlan: Session? { get }
    var history: [Session] { get }
    var rest: AppState.RestTimer? { get }
    func updateSet(_ exI: Int, _ setI: Int, weight: String?, reps: String?, time: String?, dist: String?, done: Bool?, effort: String?)
    func addSet(_ exI: Int)
    func startRest(seconds: Double, exName: String, startedAt: Date)
    func extendRest(seconds: Int)
    func stopRest()
    func finish(rpe: Int)
}

/// The iPhone half of the Apple Watch app (docs/watch.md): turns today's
/// session into the WatchState the Watch shows, and applies the Watch's
/// commands through the same AppState edits WorkoutView makes — so a set
/// logged on the wrist is saved, synced and backed up exactly like one
/// typed on the phone. The Android app's WatchSync.kt does the same over
/// the Wear OS Data Layer; this one rides WatchConnectivity:
///  • iPhone → Watch: the application context (latest state wins, waiting
///    for the Watch app to wake) plus a live message when it's reachable;
///  • Watch → iPhone: a message when reachable (which wakes this app in the
///    background), else transferUserInfo — queued until the phone is back.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private weak var app: AppState?
    /// Test hook: where snapshots go instead of WatchConnectivity.
    var sender: ((String) -> Void)?

    /// When the Watch last sent anything. While it's recent the Watch is in
    /// use, so the iPhone leaves rest alerts to it.
    private(set) var lastContact = Date.distantPast
    var watchActive: Bool { Date().timeIntervalSince(lastContact) < 30 * 60 }

    private var applied: [String] = []
    private var lastSent: String?
    private let health = HKHealthStore()

    func reset() { applied = []; lastSent = nil; lastContact = .distantPast }

    /// Called once at launch — also when the Watch woke this app in the background.
    func attach(_ app: AppState) {
        self.app = app
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The paired Watch has COACH on it.
    var watchAppInstalled: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    // MARK: - Snapshot

    func snapshot(_ app: WatchTarget, now: Date = Date()) -> WatchState {
        let acks = applied
        let sentAt = Int64(now.timeIntervalSince1970 * 1000)
        guard let t = app.todayPlan, !t.plan.exercises.isEmpty else { return WatchState(acks: acks, sentAt: sentAt) }
        if t.finished {
            return WatchState(id: t.id, type: t.plan.sessionType, title: t.plan.title, acks: acks, finished: true, sentAt: sentAt)
        }
        let exercises = t.plan.exercises.enumerated().map { i, ex -> WExercise in
            // the same hints WorkoutView's header and set rows show
            let mode = Stats.logMode(ex.name, t.plan.sessionType)
            let lastPerf = Stats.lastPerformance(app.history, ex.name)
            let suggest = mode == "strength" ? Stats.suggestNextWeight(lastPerf, ex.reps) : nil
            let leading = (Stats.firstMatch(#"^\s*(\d+(?:\.\d+)?)"#, in: ex.suggestedWeight)?[safe: 1] ?? nil).flatMap { Double($0) }
            let rows = t.log[safe: i] ?? []
            return WExercise(
                name: ex.name, mode: mode, reps: ex.reps, rpe: ex.rpe,
                restSec: Int(WorkoutView.parseRestSeconds(ex.rest)),
                target: mode == "strength" ? (suggest ?? leading).map(Helpers.fmtKg) ?? "" : "",
                last: lastPerf?.sets.map(\.formatted).joined(separator: ", ") ?? "",
                superset: ex.superset,
                sets: rows.enumerated().map { j, s in
                    let last = lastPerf?.sets[safe: j]
                    return WSet(w: s.weight, r: s.reps, t: s.time, d: s.dist, done: s.done, e: s.effort,
                                pw: suggest.map(Helpers.fmtKg) ?? last?.weight ?? "", pr: last?.reps ?? "", pt: last?.time ?? "")
                }
            )
        }
        return WatchState(
            active: true, id: t.id, type: t.plan.sessionType, title: t.plan.title, startedAt: Int64(t.startedAt),
            exercises: exercises,
            rest: app.rest.map { WRest(endsAt: Int64($0.endsAt.timeIntervalSince1970 * 1000), total: Int($0.total), ex: $0.exName) },
            acks: acks, sentAt: sentAt
        )
    }

    /// Sends the current state when it changed (or always, with `force` —
    /// the Watch asked, or a command was just applied).
    func publish(force: Bool = false) {
        guard let app else { return }
        publish(AppTarget(app), force: force)
    }

    private func publish(_ app: WatchTarget, force: Bool) {
        var s = snapshot(app)
        let sentAt = s.sentAt
        s.sentAt = 0
        let key = s.toJson()
        if !force && key == lastSent { return }
        lastSent = key
        s.sentAt = sentAt
        send(s.toJson())
    }

    private func send(_ json: String) {
        if let sender { sender(json); return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext([WatchPaths.stateKey: json])
        if session.isReachable {
            session.sendMessage([WatchPaths.stateKey: json], replyHandler: nil, errorHandler: nil)
        }
    }

    /// A workout just started on the iPhone: open COACH on the Watch, with
    /// its workout session (heart rate, energy) already running.
    func workoutStarted(sessionType: String) {
        guard WCSession.isSupported(), WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = workoutActivityType(sessionType)
        config.locationType = .indoor
        health.startWatchApp(with: config) { _, _ in }
    }

    // MARK: - Commands

    private static let efforts: Set<String> = ["", "easy", "good", "grind"]

    /// Applies one command from the Watch.
    func handle(_ app: WatchTarget, _ cmd: WatchCommand, now: Date = Date()) {
        lastContact = now
        if applied.contains(cmd.id) { publish(app, force: true); return } // a redelivery
        applied.append(cmd.id)
        if applied.count > 40 { applied.removeFirst(applied.count - 40) }

        let t = app.todayPlan
        let live = t.map { !$0.finished && (cmd.session.isEmpty || cmd.session == $0.id) } ?? false
        let snap = snapshot(app, now: now)
        let i = snap.exerciseIndex(cmd)
        switch cmd.cmd {
        case WatchCommand.logSet:
            guard live, let i else { break }
            let ex = snap.exercises[i]
            switch ex.mode {
            case "strength": app.updateSet(i, cmd.set, weight: cmd.w, reps: cmd.r, time: nil, dist: nil, done: true, effort: nil)
            case "cardio": app.updateSet(i, cmd.set, weight: nil, reps: nil, time: cmd.t, dist: cmd.d, done: true, effort: nil)
            default: app.updateSet(i, cmd.set, weight: nil, reps: nil, time: nil, dist: nil, done: true, effort: nil)
            }
            LocalStore.shared.logEvent(type: "watch_set_logged", data: ["exercise": .string(ex.name)])
            // rest runs from when the set was logged on the wrist
            let at = cmd.at > 0 ? min(Date(timeIntervalSince1970: Double(cmd.at) / 1000), now) : now
            app.startRest(seconds: Double(ex.restSec), exName: ex.name, startedAt: at)
        case WatchCommand.undoSet:
            if live, let i { app.updateSet(i, cmd.set, weight: nil, reps: nil, time: nil, dist: nil, done: false, effort: nil) }
        case WatchCommand.effort:
            if live, let i, Self.efforts.contains(cmd.effort) { app.updateSet(i, cmd.set, weight: nil, reps: nil, time: nil, dist: nil, done: nil, effort: cmd.effort) }
        case WatchCommand.addSet:
            if live, let i { app.addSet(i) }
        case WatchCommand.restSkip:
            if live { app.stopRest() }
        case WatchCommand.restAdd:
            if live { app.extendRest(seconds: min(max(cmd.sec, 5), 300)) }
        case WatchCommand.finish:
            if live {
                LocalStore.shared.logEvent(type: "watch_finished", data: [:])
                app.finish(rpe: (1...10).contains(cmd.rpe) ? cmd.rpe : 7)
            }
        default:
            break // sync: just answer · workout: the Apple Watch saves its own to Health
        }
        publish(app, force: true)
    }

    /// A command arrived (maybe with the app just woken in the background):
    /// wait until the account is open, then apply it.
    private func deliver(_ cmd: WatchCommand) async {
        for _ in 0..<200 where app == nil || app?.screen == .loading {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let app, app.screen != .loading, app.screen != .login else { return }
        handle(AppTarget(app), cmd)
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        guard let json = payload[WatchPaths.commandKey] as? String, let cmd = WatchCommand.fromJson(json) else { return }
        Task { @MainActor in await WatchSync.shared.deliver(cmd) }
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WatchSync.shared.publish(force: true) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate() // switched to another Watch
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
}

/// AppState as the Watch sees it.
@MainActor
private final class AppTarget: WatchTarget {
    let app: AppState
    init(_ app: AppState) { self.app = app }

    var todayPlan: Session? { app.todayPlan }
    var history: [Session] { app.history }
    var rest: AppState.RestTimer? { app.rest }

    func updateSet(_ exI: Int, _ setI: Int, weight: String?, reps: String?, time: String?, dist: String?, done: Bool?, effort: String?) {
        app.updateSet(exI, setI, weight: weight, reps: reps, time: time, dist: dist, done: done, effort: effort)
    }
    func addSet(_ exI: Int) { app.adjustSets(exI, 1) }
    func startRest(seconds: Double, exName: String, startedAt: Date) {
        app.startRest(seconds: seconds, exName: exName, startedAt: startedAt, fromWatch: true)
    }
    func extendRest(seconds: Int) { app.extendRest(seconds: seconds) }
    func stopRest() { app.stopRest() }
    func finish(rpe: Int) {
        app.fin = FinishInfo(rpe: rpe)
        Task { await app.finishSession() }
    }
}
