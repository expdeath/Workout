import Foundation

/// Values ⇄ Firestore document data — a port of src/db/firestoreCodec.js,
/// so both apps read and write identical documents (schema:
/// docs/firestore.md). Pure Foundation: no Firebase types, so it's unit
/// tested without the SDK.
///
/// Firestore can't hold an array directly inside an array (a session's
/// `log` is [[set]]) and reserves some field names, so:
///   an array inside an array  → { "__a": [...] }
///   an object with a key Firestore can't hold ("" or "__…")
///                             → { "__m": [{ "k": key, "v": value }, …] }
/// Lossless for any JSON value.
enum FirestoreCodec {
    private static let arr = "__a"
    private static let map = "__m"

    private static func badKey(_ k: String) -> Bool { k.isEmpty || k.hasPrefix("__") }

    // ── JSONValue → Firestore value ──────────────────────────────

    static func encode(_ v: JSONValue, inArray: Bool = false) -> Any {
        switch v {
        case .array(let a):
            let out = a.map { encode($0, inArray: true) }
            return inArray ? [arr: out] : out
        case .object(let o):
            if o.keys.contains(where: badKey) {
                return [map: o.keys.sorted().map { ["k": $0, "v": encode(o[$0]!)] }]
            }
            return o.mapValues { encode($0) }
        case .string(let s): return s
        case .bool(let b): return b
        case .null: return NSNull()
        case .number(let n):
            // whole numbers go out as integers, like the web SDK writes
            // JS numbers (ms timestamps, counts) — doubles otherwise
            if n.rounded() == n, abs(n) < 9_007_199_254_740_992 { return Int64(n) }
            return n
        }
    }

    // ── Firestore value → JSONValue ──────────────────────────────

    static func decode(_ any: Any) -> JSONValue {
        switch any {
        case let n as NSNumber:
            // Firestore hands booleans back as NSNumber too
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map(decode))
        case let d as [String: Any]:
            if d.count == 1, let inner = d[arr] as? [Any] { return .array(inner.map(decode)) }
            if d.count == 1, let pairs = d[map] as? [[String: Any]] {
                var out: [String: JSONValue] = [:]
                for p in pairs { if let k = p["k"] as? String { out[k] = decode(p["v"] ?? NSNull()) } }
                return .object(out)
            }
            return .object(d.mapValues(decode))
        default:
            return .null // NSNull, or a Firestore type this app never writes
        }
    }

    // ── Documents ────────────────────────────────────────────────

    /// A model → the data to write as one document.
    static func document<T: Encodable>(_ value: T) throws -> [String: Any] {
        guard let d = encode(try JSONValue.encoding(value)) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return d
    }

    /// One document's data → a model (decoded leniently by the model).
    static func model<T: Decodable>(_ type: T.Type, from data: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(decode(data)))
    }

    /// Document ids can't contain "/" or be "." / ".." / "__…__"; the real
    /// key always also lives inside the document, so ids are just lookups.
    static func docId(_ raw: String) -> String {
        let esc = raw.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F")
        if esc.isEmpty || esc == "." || esc == ".." || (esc.hasPrefix("__") && esc.hasSuffix("__") && esc.count >= 4) {
            return "%" + esc
        }
        return esc
    }

    /// Same key the merge dedupes the event log by (src/db/backupShape.js).
    static func eventDocId(_ e: Event) -> String { docId("\(e.iso)|\(e.type)") }
}
