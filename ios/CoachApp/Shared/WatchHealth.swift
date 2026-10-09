import HealthKit

/// Apple Health's activity for a COACH session type — the iPhone uses it
/// to launch the Watch's workout, the Watch to start one itself.
/// (HealthConnectSync.exerciseType / WorkoutService.exerciseType on Android.)
nonisolated func workoutActivityType(_ sessionType: String) -> HKWorkoutActivityType {
    switch sessionType.lowercased() {
    case "run": return .running
    case "cycle": return .cycling
    case "walk": return .walking
    case "hike": return .hiking
    case "stretch & mobility", "active recovery": return .flexibility
    case "cardio": return .mixedCardio
    case "core": return .coreTraining
    default: return .traditionalStrengthTraining
    }
}
