import Foundation
import Observation
import WatchConnectivity

/// The Watch's view of the iPhone's workout (docs/watch.md). Holds the
/// phone's last WatchState plus the commands sent since, and shows the two
/// combined — so a tap on the wrist shows up instantly, works with the
/// iPhone out of range (transferUserInfo queues the command), and is
/// replaced by the phone's real answer when it arrives. Both halves are
/// kept on disk: the app can be suspended between sets.
/// (PhoneLink.kt is the Wear OS twin.)
@MainActor
@Observable
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    /// What to show: the phone's state with this watch's pending commands applied.
    private(set) var state = WatchState()
    /// The iPhone is in range right now.
    private(set) var reachable = false

    @ObservationIgnored private var phone = WatchState()
    @ObservationIgnored private var pending: [WatchCommand] = []
    @ObservationIgnored private let defaults = UserDefaults.standard

    func start() {
        phone = defaults.string(forKey: "phone").flatMap(WatchState.fromJson) ?? WatchState()
        pending = (defaults.stringArray(forKey: "pending") ?? []).compactMap(WatchCommand.fromJson).sorted { $0.at < $1.at }
        #if DEBUG
        // launch argument -COACH_DEBUG_SEED workout|rest|idle|done: a canned workout, no iPhone needed
        if let seed = defaults.string(forKey: "COACH_DEBUG_SEED") { phone = DebugStates.state(seed); pending = [] }
        #endif
        publish()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func publish() {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - 30 * 60_000
        // applied by the phone, or too old to still matter
        pending = pending.filter { !phone.acks.contains($0.id) && $0.at > cutoff }
        defaults.set(phone.toJson(), forKey: "phone")
        defaults.set(pending.map { $0.toJson() }, forKey: "pending")
        state = phone.withPending(pending)
        WorkoutManager.shared.stateChanged(state)
    }

    /// A state snapshot from the iPhone.
    func receive(_ json: String) {
        guard let s = WatchState.fromJson(json) else { return }
        if s.sentAt > 0 && s.sentAt < phone.sentAt { return } // an older copy arriving late
        phone = s
        publish()
    }

    /// Applies a command here at once and sends it to the iPhone.
    func send(_ cmd: String, ex: Int = -1, name: String = "", set: Int = -1, w: String = "", r: String = "", t: String = "", d: String = "",
              effort: String = "", sec: Int = 0, rpe: Int = 0) {
        let c = WatchCommand(id: UUID().uuidString, at: Int64(Date().timeIntervalSince1970 * 1000), cmd: cmd, session: state.id,
                             ex: ex, name: name, set: set, w: w, r: r, t: t, d: d, effort: effort, sec: sec, rpe: rpe)
        if cmd != WatchCommand.sync {
            pending.append(c)
            publish()
        }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = [WatchPaths.commandKey: c.toJson()]
        let session = WCSession.default
        if session.isReachable {
            // live; on failure fall back to the queue (the iPhone ignores a repeat)
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in session.transferUserInfo(payload) })
        } else if cmd != WatchCommand.sync {
            session.transferUserInfo(payload)
        }
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext[WatchPaths.stateKey] as? String
        let reachable = session.isReachable
        Task { @MainActor in
            let link = PhoneLink.shared
            if let context { link.receive(context) }
            link.reachable = reachable
            link.send(WatchCommand.sync)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            PhoneLink.shared.reachable = reachable
            if reachable { PhoneLink.shared.send(WatchCommand.sync) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    nonisolated private func deliver(_ payload: [String: Any]) {
        guard let json = payload[WatchPaths.stateKey] as? String else { return }
        Task { @MainActor in PhoneLink.shared.receive(json) }
    }
}

#if DEBUG
/// Canned states for screenshots (the same ones the Wear OS app has).
enum DebugStates {
    static func state(_ kind: String) -> WatchState {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let ex = [
            WExercise(name: "Bench Press", reps: "6-8", restSec: 120, target: "62.5", last: "60kg×8, 60kg×8, 60kg×7",
                      sets: [WSet(w: "60", r: "8", done: true, e: "good", pw: "62.5", pr: "8"), WSet(pw: "62.5", pr: "8"), WSet(pw: "62.5", pr: "7")]),
            WExercise(name: "Incline Dumbbell Press", reps: "8-10", restSec: 90, target: "22", sets: Array(repeating: WSet(pw: "22", pr: "10"), count: 3)),
            WExercise(name: "Cable Fly", reps: "12-15", restSec: 60, sets: Array(repeating: WSet(), count: 3)),
            WExercise(name: "Plank", mode: "check", reps: "3 × 45s", restSec: 45, sets: Array(repeating: WSet(), count: 2)),
        ]
        switch kind {
        case "idle": return WatchState(sentAt: now)
        case "done": return WatchState(title: "Push — strength", finished: true, sentAt: now)
        case "rest": return WatchState(active: true, id: "dbg", type: "Push", title: "Push — strength", startedAt: now - 23 * 60_000,
                                       exercises: ex, rest: WRest(endsAt: now + 74_000, total: 120, ex: "Bench Press"), sentAt: now)
        default: return WatchState(active: true, id: "dbg", type: "Push", title: "Push — strength", startedAt: now - 23 * 60_000, exercises: ex, sentAt: now)
        }
    }
}
#endif
