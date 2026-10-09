import HealthKit
import SwiftUI
import WatchKit

/// COACH on the wrist: only what you'd otherwise take the iPhone out for
/// between sets — what's next, log it, rest, rate it, finish. Planning,
/// check-ins, history and the AI all stay on the phone.
@main
struct CoachWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchDelegate

    init() {
        PhoneLink.shared.start()
    }

    var body: some Scene {
        WindowGroup { WatchRoot() }
    }
}

/// The iPhone starts a workout → watchOS launches this app with its
/// configuration (HKHealthStore.startWatchApp in WatchSync.swift).
final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WorkoutManager.shared.start(workoutConfiguration) }
    }
}
