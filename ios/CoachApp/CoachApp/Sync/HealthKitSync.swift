import Foundation
import HealthKit

/// Apple Health → the account's health rows — replaces the Gym Check-in
/// Shortcut → GitHub health-inbox pipeline (decided 2026-10-07; the inbox
/// is still drained, so both can run side by side while switching over).
///
/// Reads the metrics the Shortcut sent, per calendar day, and writes them
/// the way the rest of the system already understands: typed fields on
/// the day's HealthRow (mergeHealth — never clobbers fields another
/// source wrote) plus the same "HRVavg(ms): … SleepHrs: …" text the
/// Shortcut produced, which pre-fills today's check-in (healthText-<date>)
/// and feeds the AI. HealthKit's statistics queries de-duplicate Watch +
/// iPhone samples, and sleep intervals are merged — so the Shortcut's
/// "sleep doubled by two sources" problem can't happen here.
final class HealthKitSync {
    static let shared = HealthKitSync()
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Whether the permission sheet has been shown on this device (iOS
    /// never reveals whether *read* access was granted — by design).
    static var requested: Bool {
        get { Defaults.string("healthkit-requested") == "1" }
        set { Defaults.set(newValue ? "1" : nil, for: "healthkit-requested") }
    }

    private static let quantityIds: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN, .restingHeartRate, .stepCount, .vo2Max, .activeEnergyBurned,
        .appleExerciseTime, .distanceWalkingRunning, .respiratoryRate, .appleSleepingWristTemperature,
        .bodyMass, .oxygenSaturation,
    ]

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>(Self.quantityIds.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    /// Shows Apple's Health permission sheet (once; later calls are no-ops
    /// unless new types were added).
    func requestAccess() async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        Self.requested = true
    }

    // MARK: - Sync

    /// Today plus any of the last `days` days with no row yet. Returns how
    /// many days were written.
    /// Bump when how a day is read changes: the next sync re-reads every
    /// day in range once (not only missing ones), fixing stored rows.
    private static let readVersion = "2" // 2: wrist temperature by night

    @discardableResult
    func sync(days: Int = 7) async -> Int {
        guard Self.isAvailable, Self.requested, Cloud.shared.account != nil || Cloud.shared.offline else { return 0 }
        let reread = Defaults.string("healthkit-read-version") != Self.readVersion
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let have = Set(LocalStore.shared.backup.health.map(\.date))
        var written = 0
        for back in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let iso = Self.iso(day)
            // past days: only fill gaps (a finished day doesn't change);
            // today: always refresh — steps/kcal keep climbing
            if back > 0 && have.contains(iso) && !reread { continue }
            let m = await readDay(day)
            guard !m.isEmpty else { continue }
            let text = m.shortcutText
            LocalStore.shared.mergeHealth(HealthRow(
                date: iso, hrv: m.hrv, rhr: m.rhr, steps: m.steps, sleepH: m.sleepH, weightKg: m.weightKg,
                respRate: m.respRate, wristC: m.wristC, vo2max: m.vo2max, kcal: m.kcal,
                exerciseMin: m.exerciseMin, distKm: m.distKm, spo2: m.spo2, raw: String(text.prefix(300))
            ))
            if back == 0 { Cloud.shared.setState("healthText-\(iso)", .string(text)) }
            written += 1
        }
        if reread && days >= 7 { Defaults.set(Self.readVersion, for: "healthkit-read-version") }
        if written > 0 { LocalStore.shared.logEvent(type: "healthkit_synced", data: ["days": .number(Double(written))]) }
        return written
    }

    // MARK: - One day

    struct DayMetrics: Equatable {
        var hrv, rhr, steps, sleepH, vo2max, kcal, exerciseMin, distKm, respRate, wristC, weightKg, spo2: Double?

        var isEmpty: Bool { [hrv, rhr, steps, sleepH, vo2max, kcal, exerciseMin, distKm, respRate, wristC, weightKg, spo2].allSatisfy { $0 == nil } }

        /// The Gym Check-in Shortcut's text format, so parseHealthNumbers
        /// (both apps) reads it exactly like a Shortcut delivery. Sleep is
        /// in hours (≤20 → taken as hours by the parser).
        var shortcutText: String {
            func f(_ v: Double?, _ digits: Int = 1) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "" }
            return [
                "HRVavg(ms): \(f(hrv))", "RHRavg(bpm): \(f(rhr))", "StepsToday: \(f(steps, 0))",
                "SleepHrs: \(f(sleepH, 2))", "VO2Max: \(f(vo2max))", "ActiveKcal: \(f(kcal, 0))",
                "ExerciseMin: \(f(exerciseMin, 0))", "DistanceKm: \(f(distKm, 2))",
                "RespRate(brpm): \(f(respRate))", "WristTemp: \(f(wristC, 2))",
                weightKg.map { "Weight \(String(format: "%.1f", $0))kg" } ?? "",
                spo2.map { "SpO2 \(String(format: "%.0f", $0))%" } ?? "",
            ]
            .filter { !$0.hasSuffix(": ") && !$0.isEmpty }
            .joined(separator: " ")
        }
    }

    func readDay(_ dayStart: Date) async -> DayMetrics {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        async let hrv = stat(.heartRateVariabilitySDNN, .discreteAverage, dayStart, end, HKUnit.secondUnit(with: .milli))
        async let rhr = stat(.restingHeartRate, .discreteAverage, dayStart, end, HKUnit.count().unitDivided(by: .minute()))
        async let steps = stat(.stepCount, .cumulativeSum, dayStart, end, .count())
        async let kcal = stat(.activeEnergyBurned, .cumulativeSum, dayStart, end, .kilocalorie())
        async let exMin = stat(.appleExerciseTime, .cumulativeSum, dayStart, end, .minute())
        async let dist = stat(.distanceWalkingRunning, .cumulativeSum, dayStart, end, .meterUnit(with: .kilo))
        async let resp = stat(.respiratoryRate, .discreteAverage, dayStart, end, HKUnit.count().unitDivided(by: .minute()))
        // a per-night reading: the night that ends on this day (18:00 the
        // evening before → 14:00), like sleep — not the day it started
        async let wrist = stat(.appleSleepingWristTemperature, .discreteAverage,
                               Calendar.current.date(byAdding: .hour, value: -6, to: dayStart)!,
                               Calendar.current.date(byAdding: .hour, value: 14, to: dayStart)!, .degreeCelsius())
        async let spo2 = stat(.oxygenSaturation, .discreteAverage, dayStart, end, .percent())
        // VO₂max is measured every few days — the latest value up to this day
        async let vo2 = latest(.vo2Max, before: end, within: 30, HKUnit(from: "ml/kg*min"))
        async let weight = latest(.bodyMass, before: end, within: 1, .gramUnit(with: .kilo))
        async let sleep = sleepHours(endingOn: dayStart)
        var m = DayMetrics()
        m.hrv = await hrv
        m.rhr = await rhr
        m.steps = await steps.map { $0.rounded() }
        m.kcal = await kcal
        m.exerciseMin = await exMin
        m.distKm = await dist
        m.respRate = await resp
        m.wristC = await wrist
        m.spo2 = await spo2.map { $0 * 100 }
        m.vo2max = await vo2
        m.weightKg = await weight
        m.sleepH = await sleep
        return m
    }

    private func stat(_ id: HKQuantityTypeIdentifier, _ opt: HKStatisticsOptions, _ start: Date, _ end: Date, _ unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            store.execute(HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: opt) { _, s, _ in
                let q = opt.contains(.cumulativeSum) ? s?.sumQuantity() : s?.averageQuantity()
                cont.resume(returning: q.map { $0.doubleValue(for: unit) })
            })
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, before end: Date, within days: Int, _ unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { cont in
            store.execute(HKSampleQuery(sampleType: type, predicate: pred, limit: 1,
                                        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            })
        }
    }

    /// The night ending on this day: asleep intervals between 18:00 the
    /// evening before and 14:00 this day, from every source, merged so
    /// Watch + iPhone overlap is counted once.
    private func sleepHours(endingOn day: Date) async -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -6, to: day)!
        let end = cal.date(byAdding: .hour, value: 14, to: day)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let asleep: Set<Int> = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let intervals: [DateInterval] = await withCheckedContinuation { cont in
            store.execute(HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample] ?? [])
                    .filter { asleep.contains($0.value) }
                    .map { DateInterval(start: max($0.startDate, start), end: min($0.endDate, end)) })
            })
        }
        let hours = Self.mergedDuration(intervals) / 3600
        return hours > 0 ? (hours * 100).rounded() / 100 : nil
    }

    /// Total time covered by possibly-overlapping intervals.
    static func mergedDuration(_ intervals: [DateInterval]) -> TimeInterval {
        var total: TimeInterval = 0
        var cur: DateInterval?
        for iv in intervals.sorted(by: { $0.start < $1.start }) where iv.duration > 0 {
            if let c = cur, iv.start <= c.end {
                cur = DateInterval(start: c.start, end: max(c.end, iv.end))
            } else {
                if let c = cur { total += c.duration }
                cur = iv
            }
        }
        return total + (cur?.duration ?? 0)
    }

    private static func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: d)
    }
}
