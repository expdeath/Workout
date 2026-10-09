import Foundation

/// One day of Apple Watch / typed-in health data. Mirrors the `health`
/// object store in src/db/db.js (putHealth/mergeHealth) — fields beyond
/// the core Watch signals are filled in as Stats.swift (stats.js port,
/// Phase 4) needs them; mergeHealth() on the JS side patches whatever
/// subset of keys a given source provides, so every field here stays
/// optional.
struct HealthRow: Codable, Equatable {
    var date: String
    var hrv: Double? = nil
    var rhr: Double? = nil
    var steps: Double? = nil
    var sleepH: Double? = nil
    var weightKg: Double? = nil
    var respRate: Double? = nil
    var wristC: Double? = nil
    var vo2max: Double? = nil
    var raw: String? = nil
    var receivedAt: Double? = nil
}
