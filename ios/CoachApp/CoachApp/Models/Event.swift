import Foundation

/// Append-only interaction log entry. Mirrors logEvent() in
/// src/db/db.js — `data` is intentionally free-form since every event
/// type (checkin_submitted, plan_generated, sync_failed, ...) carries a
/// different payload.
struct Event: RawPreserving, Equatable {
    var ts: Double
    var iso: String
    var type: String
    var data: [String: JSONValue] = [:]
    var source: RawSource? = nil

    enum CodingKeys: String, CodingKey { case ts, iso, type, data }

    init(ts: Double, iso: String, type: String, data: [String: JSONValue] = [:]) {
        self.ts = ts; self.iso = iso; self.type = type; self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = c.lenientString(.type), !type.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "event without a type")
        }
        self.type = type
        ts = c.lenientDouble(.ts) ?? 0
        iso = c.lenientString(.iso) ?? ""
        data = c.lenient([String: JSONValue].self, .data) ?? [:]
        try rememberSource(from: decoder)
    }

    func encodeKnown(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ts, forKey: .ts)
        try c.encode(iso, forKey: .iso)
        try c.encode(type, forKey: .type)
        try c.encode(data, forKey: .data)
    }

    func encode(to encoder: Encoder) throws { try encodePreserving(to: encoder) }
}
