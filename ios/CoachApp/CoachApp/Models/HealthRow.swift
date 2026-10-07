import Foundation

/// One day of Apple Watch / typed-in health data. Mirrors the `health`
/// object store in src/db/db.js (putHealth/mergeHealth) and every field
/// parseHealthNumbers() in src/utils/stats.js can fill. mergeHealth()
/// patches whatever subset of keys a given source provides, so every
/// field stays optional; keys this model doesn't know survive a round
/// trip untouched (RawPreserving.swift).
struct HealthRow: RawPreserving, Equatable {
    var date: String
    var hrv: Double? = nil
    var rhr: Double? = nil
    var steps: Double? = nil
    var sleepH: Double? = nil
    var weightKg: Double? = nil
    var respRate: Double? = nil
    var wristC: Double? = nil
    var vo2max: Double? = nil
    var kcal: Double? = nil
    var exerciseMin: Double? = nil
    var distKm: Double? = nil
    var spo2: Double? = nil
    var raw: String? = nil
    var receivedAt: Double? = nil
    var source: RawSource? = nil

    enum CodingKeys: String, CodingKey {
        case date, hrv, rhr, steps, sleepH, weightKg, respRate, wristC, vo2max, kcal, exerciseMin, distKm, spo2, raw, receivedAt
    }

    /// The metric fields, for code that patches or copies them generically.
    static let metricKeys: [WritableKeyPath<HealthRow, Double?>] = [
        \.hrv, \.rhr, \.steps, \.sleepH, \.weightKg, \.respRate, \.wristC, \.vo2max, \.kcal, \.exerciseMin, \.distKm, \.spo2,
    ]

    init(date: String, hrv: Double? = nil, rhr: Double? = nil, steps: Double? = nil, sleepH: Double? = nil, weightKg: Double? = nil, respRate: Double? = nil, wristC: Double? = nil, vo2max: Double? = nil, kcal: Double? = nil, exerciseMin: Double? = nil, distKm: Double? = nil, spo2: Double? = nil, raw: String? = nil, receivedAt: Double? = nil) {
        self.date = date; self.hrv = hrv; self.rhr = rhr; self.steps = steps; self.sleepH = sleepH
        self.weightKg = weightKg; self.respRate = respRate; self.wristC = wristC; self.vo2max = vo2max
        self.kcal = kcal; self.exerciseMin = exerciseMin; self.distKm = distKm; self.spo2 = spo2
        self.raw = raw; self.receivedAt = receivedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let date = c.lenientString(.date), !date.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "health row without a date")
        }
        self.date = date
        hrv = c.lenientDouble(.hrv); rhr = c.lenientDouble(.rhr); steps = c.lenientDouble(.steps)
        sleepH = c.lenientDouble(.sleepH); weightKg = c.lenientDouble(.weightKg)
        respRate = c.lenientDouble(.respRate); wristC = c.lenientDouble(.wristC)
        vo2max = c.lenientDouble(.vo2max); kcal = c.lenientDouble(.kcal)
        exerciseMin = c.lenientDouble(.exerciseMin); distKm = c.lenientDouble(.distKm)
        spo2 = c.lenientDouble(.spo2)
        raw = c.lenientString(.raw); receivedAt = c.lenientDouble(.receivedAt)
        try rememberSource(from: decoder)
    }

    func encodeKnown(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(hrv, forKey: .hrv); try c.encodeIfPresent(rhr, forKey: .rhr)
        try c.encodeIfPresent(steps, forKey: .steps); try c.encodeIfPresent(sleepH, forKey: .sleepH)
        try c.encodeIfPresent(weightKg, forKey: .weightKg); try c.encodeIfPresent(respRate, forKey: .respRate)
        try c.encodeIfPresent(wristC, forKey: .wristC); try c.encodeIfPresent(vo2max, forKey: .vo2max)
        try c.encodeIfPresent(kcal, forKey: .kcal); try c.encodeIfPresent(exerciseMin, forKey: .exerciseMin)
        try c.encodeIfPresent(distKm, forKey: .distKm); try c.encodeIfPresent(spo2, forKey: .spo2)
        try c.encodeIfPresent(raw, forKey: .raw); try c.encodeIfPresent(receivedAt, forKey: .receivedAt)
    }

    func encode(to encoder: Encoder) throws { try encodePreserving(to: encoder) }
}
