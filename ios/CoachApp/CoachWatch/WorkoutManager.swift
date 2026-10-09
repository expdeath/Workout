import Foundation
import HealthKit
import Observation
import WatchKit

/// The Watch's workout session for the length of a COACH workout:
///  • heart rate and energy, live, from HKLiveWorkoutBuilder;
///  • the workout saved to Apple Health when the session is finished
///    (minutes, energy and heart rate count toward the rings — and the
///    iPhone's HealthKitSync reads them back into the day's row);
///  • the app keeps running with the wrist down, so the rest-over tap
///    comes on time.
/// Started by the iPhone (HKHealthStore.startWatchApp) or by opening the
/// app mid-workout; ended when the iPhone's session finishes or is
/// cancelled. (WorkoutService.kt is the Wear OS twin.)
@MainActor
@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    private(set) var heartRate: Int?
    private(set) var running = false

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var lastRest: WRest?
    @ObservationIgnored private var lastType = ""

    /// Every change to what the Watch shows passes through here (PhoneLink.publish).
    func stateChanged(_ s: WatchState) {
        if !s.type.isEmpty { lastType = s.type }
        #if DEBUG
        // canned screenshot states: no Health prompt, no session
        if UserDefaults.standard.string(forKey: "COACH_DEBUG_SEED") != nil { return }
        #endif
        if s.active {
            if !running && !starting { Task { await start(nil) } }
        } else if running {
            // finished: file it in Apple Health · cancelled on the phone: discard
            Task { await end(save: s.finished) }
        }
        if s.rest != lastRest {
            lastRest = s.rest
            scheduleRestTaps(s.active ? s.rest : nil)
        }
    }

    // MARK: - Session

    func start(_ configuration: HKWorkoutConfiguration?) async {
        guard !running, !starting, HKHealthStore.isHealthDataAvailable() else { return }
        starting = true
        defer { starting = false }
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
        let config = configuration ?? {
            let c = HKWorkoutConfiguration()
            c.activityType = workoutActivityType(lastType)
            c.locationType = .indoor
            return c
        }()
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startedAt = now
            running = true
        } catch {
            session = nil
            builder = nil
        }
    }

    func end(save: Bool) async {
        guard running, let session, let builder else { return }
        running = false
        session.end()
        try? await builder.endCollection(at: Date())
        // a few minutes of browsing isn't a workout worth filing
        if save, let startedAt, Date().timeIntervalSince(startedAt) > 5 * 60 {
            _ = try? await builder.finishWorkout()
        } else {
            builder.discardWorkout()
        }
        self.session = nil
        self.builder = nil
        heartRate = nil
    }

    // MARK: - Rest

    private func scheduleRestTaps(_ rest: WRest?) {
        restTask?.cancel()
        guard let rest else { return }
        let end = Date(timeIntervalSince1970: Double(rest.endsAt) / 1000)
        guard end.timeIntervalSinceNow > 0 else { return }
        restTask = Task { @MainActor in
            let left = end.timeIntervalSinceNow
            if left > 10 { // 10 s to go
                try? await Task.sleep(nanoseconds: UInt64((left - 10) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(.click)
            }
            try? await Task.sleep(nanoseconds: UInt64(max(end.timeIntervalSinceNow, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification) // GO
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            let m = WorkoutManager.shared
            m.running = false
            m.session = nil
            m.builder = nil
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let q = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() else { return }
        let bpm = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in WorkoutManager.shared.heartRate = bpm }
    }
}
