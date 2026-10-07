import Foundation

// ── Lossless round trips for synced documents ─────────────────────
// Sessions, health rows, events and AI settings come from JSON that
// other clients wrote (the web app, older versions of either app). The
// typed Swift models only know some of those keys, and decode some
// values loosely (a number where a String is expected, defaults for
// missing keys). Re-encoding just the typed fields would silently drop
// or rewrite everything else — and since every write goes back to the
// shared database, that loss would reach every device.
//
// So a document decoded from JSON remembers that JSON (`raw`) and what
// its typed fields encoded to right after decoding (`base`). Encoding
// it again starts from `raw` and applies only the fields whose typed
// value has actually changed since (base → current). Untouched keys —
// known or not — go back out byte-for-byte as they came in.

/// The JSON a document was decoded from. Deliberately ignored by `==`:
/// two sessions with the same typed content are the same session.
struct RawSource: Equatable {
    var raw: JSONValue
    var base: JSONValue
    static func == (lhs: RawSource, rhs: RawSource) -> Bool { true }
}

/// A model that can encode just its typed fields, and remembers the
/// JSON it was decoded from.
protocol RawPreserving: Codable {
    var source: RawSource? { get set }
    func encodeKnown(to encoder: Encoder) throws
}

private struct KnownFields<T: RawPreserving>: Encodable {
    let value: T
    func encode(to encoder: Encoder) throws { try value.encodeKnown(to: encoder) }
}

extension RawPreserving {
    /// Call at the end of `init(from:)`, after every typed field is set.
    mutating func rememberSource(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        source = RawSource(raw: raw, base: try JSONValue.encoding(KnownFields(value: self)))
    }

    /// The body of every RawPreserving type's `encode(to:)`.
    func encodePreserving(to encoder: Encoder) throws {
        guard let source else { return try encodeKnown(to: encoder) }
        let current = try JSONValue.encoding(KnownFields(value: self))
        try source.raw.applying(from: source.base, to: current).encode(to: encoder)
    }
}

extension JSONValue {
    /// Any Encodable → its JSON tree.
    static func encoding<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// `self` with the edits that turn `base` into `current` applied —
    /// recursing into objects and arrays so an edit to one set of one
    /// exercise leaves every other key of the session untouched.
    func applying(from base: JSONValue?, to current: JSONValue) -> JSONValue {
        if base == current { return self }
        switch (self, base, current) {
        case let (.object(raw), .object(b)?, .object(cur)):
            var out = raw
            for (k, cv) in cur where b[k] != cv {
                out[k] = raw[k].map { $0.applying(from: b[k], to: cv) } ?? cv
            }
            for k in b.keys where cur[k] == nil { out[k] = nil }
            return .object(out)
        case let (.array(raw), .array(b)?, .array(cur)):
            return .array(cur.indices.map { i in
                i < raw.count && i < b.count ? raw[i].applying(from: b[i], to: cur[i]) : cur[i]
            })
        default:
            return current
        }
    }
}

// ── Lenient field decoding ───────────────────────────────────────
// Real synced data mixes types for the same field (the AI returns
// `rpe` as a number some days and a string on others; hand-entered
// values arrive as strings). These never throw on a type mismatch —
// they coerce, or return nil so the caller's default applies.

extension KeyedDecodingContainer {
    private func json(_ key: Key) -> JSONValue? {
        guard contains(key), let v = try? decode(JSONValue.self, forKey: key) else { return nil }
        if case .null = v { return nil }
        return v
    }

    func lenientString(_ key: Key) -> String? {
        switch json(key) {
        case .string(let s)?: return s
        case .number(let n)?: return n.rounded() == n && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b)?: return b ? "true" : "false"
        default: return nil
        }
    }

    func lenientDouble(_ key: Key) -> Double? {
        switch json(key) {
        case .number(let n)?: return n
        case .string(let s)?: return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b)?: return b ? 1 : 0
        default: return nil
        }
    }

    func lenientInt(_ key: Key) -> Int? {
        guard let d = lenientDouble(key), d.isFinite, abs(d) < 1e15 else { return nil }
        return Int(d.rounded())
    }

    func lenientBool(_ key: Key) -> Bool? {
        switch json(key) {
        case .bool(let b)?: return b
        case .number(let n)?: return n != 0
        case .string(let s)?: return ["true", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }

    func lenientStrings(_ key: Key) -> [String]? {
        guard case .array(let a)? = json(key) else { return nil }
        return a.compactMap {
            switch $0 {
            case .string(let s): return s
            case .number(let n): return n.rounded() == n ? String(Int64(n)) : String(n)
            default: return nil
            }
        }
    }

    /// Decodes a nested value, nil instead of throwing when it's malformed.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        guard json(key) != nil else { return nil }
        return try? decode(T.self, forKey: key)
    }
}

/// Decodes an array element by element, keeping (as raw JSON) any
/// element that doesn't fit the model, so one odd row can neither fail
/// the whole array nor be dropped on the next write.
struct LossyArray<T: Decodable>: Decodable {
    var items: [T] = []
    var unparsed: [JSONValue] = []

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            let v = try c.decode(JSONValue.self)
            if let item = try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(v)) {
                items.append(item)
            } else {
                unparsed.append(v)
            }
        }
    }
}
