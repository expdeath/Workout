import Foundation

/// Append-only interaction log entry. Mirrors logEvent() in
/// src/db/db.js — `data` is intentionally free-form since every event
/// type (checkin_submitted, plan_generated, sync_failed, ...) carries a
/// different payload.
struct Event: Codable, Equatable {
    var ts: Double
    var iso: String
    var type: String
    var data: [String: JSONValue] = [:]

    init(ts: Double, iso: String, type: String, data: [String: JSONValue] = [:]) {
        self.ts = ts; self.iso = iso; self.type = type; self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decodeIfPresent(Double.self, forKey: .ts) ?? 0
        iso = try c.decodeIfPresent(String.self, forKey: .iso) ?? ""
        type = try c.decode(String.self, forKey: .type)
        data = try c.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
    }
}
