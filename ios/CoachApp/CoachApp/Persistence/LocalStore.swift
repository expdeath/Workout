import Foundation

/// The signed-in account's data, in memory, in the same `Backup` shape
/// the screens and stats have always read (sessions/health/deletedIds/
/// aiSettings). Cloud.swift keeps it live from Firestore snapshot
/// listeners (`applyRemote…`), and every mutation here writes through to
/// Firestore — whose own offline cache is what persists data on device.
/// The event log is write-only (Cloud.allEvents fetches it on demand),
/// except with Cloud.offline (DebugSeed), where everything stays here.
@MainActor
@Observable
final class LocalStore {
    static let shared = LocalStore()

    private(set) var backup = Backup()

    private init() {}

    private var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    // ── Local mutations (write through to Firestore) ─────────────

    /// Mirrors putSession() in src/db/db.js: updatedAt makes this the
    /// newest copy (firestore.rules refuse a write older than the stored one).
    func upsert(session: Session) {
        var s = session
        s.updatedAt = now
        if let i = backup.sessions.firstIndex(where: { $0.id == s.id }) {
            backup.sessions[i] = s
        } else {
            backup.sessions.append(s)
        }
        Cloud.shared.putSession(s)
    }

    /// Removes the session for real and records a permanent marker, so
    /// no device can bring it back (mirrors hardDeleteSession()).
    func hardDelete(sessionId: String) {
        let at = now
        backup.sessions.removeAll { $0.id == sessionId }
        backup.deletedIds.removeAll { $0.id == sessionId }
        backup.deletedIds.append(DeletedId(id: sessionId, at: at))
        Cloud.shared.deleteSession(id: sessionId, at: at)
    }

    /// "Clear all history" — every session removed and marked deleted.
    func clearSessions() {
        let at = now
        let ids = backup.sessions.map(\.id)
        backup.sessions = []
        for id in ids {
            backup.deletedIds.removeAll { $0.id == id }
            backup.deletedIds.append(DeletedId(id: id, at: at))
        }
        Cloud.shared.clearSessions(ids: ids, at: at)
    }

    func logEvent(type: String, data: [String: JSONValue] = [:]) {
        let e = Event(ts: now, iso: ISO8601DateFormatter.withMillis.string(from: Date()), type: type, data: data)
        if Cloud.shared.offline { backup.events.append(e) }
        Cloud.shared.logEvent(e)
    }

    /// Mirrors setAISettings() in src/utils/storage.js — patch + stamp
    /// updatedAt so newest-wins holds across devices.
    func updateAISettings(_ patch: (inout AISettings) -> Void) {
        patch(&backup.aiSettings)
        backup.aiSettings.updatedAt = now
        Cloud.shared.putAISettings(backup.aiSettings)
    }

    /// Patch a day's row without clobbering fields another source wrote
    /// (mirrors mergeHealth() in src/db/db.js).
    func mergeHealth(_ patch: HealthRow) {
        var row: HealthRow
        if let i = backup.health.firstIndex(where: { $0.date == patch.date }) {
            row = backup.health[i]
            for k in HealthRow.metricKeys { if let v = patch[keyPath: k] { row[keyPath: k] = v } }
            if let v = patch.raw { row.raw = v }
            row.receivedAt = patch.receivedAt ?? now
            backup.health[i] = row
        } else {
            row = patch
            row.receivedAt = row.receivedAt ?? now
            backup.health.append(row)
        }
        Cloud.shared.putHealth(row)
    }

    // ── Remote changes (from Cloud's snapshot listeners) ─────────

    func resetMirror() { backup = Backup() }

    private func decode<T: Decodable>(_ type: T.Type, _ v: JSONValue) -> T? {
        try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(v))
    }

    func applyRemoteSessions(_ changes: [(String, JSONValue?)]) {
        for (docId, value) in changes {
            backup.sessions.removeAll { FirestoreCodec.docId($0.id) == docId }
            if let value, let s = decode(Session.self, value) { backup.sessions.append(s) }
        }
    }

    func applyRemoteHealth(_ changes: [(String, JSONValue?)]) {
        for (docId, value) in changes {
            backup.health.removeAll { FirestoreCodec.docId($0.date) == docId }
            if let value, let h = decode(HealthRow.self, value) { backup.health.append(h) }
        }
        backup.health.sort { $0.date < $1.date }
    }

    func applyRemoteDeletedIds(_ changes: [(String, JSONValue?)]) {
        for (docId, value) in changes {
            backup.deletedIds.removeAll { FirestoreCodec.docId($0.id) == docId }
            if let value, let d = decode(DeletedId.self, value) { backup.deletedIds.append(d) }
        }
    }

    func applyRemoteAISettings(_ value: JSONValue?) {
        backup.aiSettings = value.flatMap { decode(AISettings.self, $0) } ?? AISettings()
    }

    // ── Debug / sign-out ─────────────────────────────────────────

    /// DebugSeed only: seed rows without a cloud round trip.
    func seed(session: Session) { backup.sessions.append(session) }

    func wipe() { backup = Backup() }
}

extension ISO8601DateFormatter {
    /// `2026-10-07T06:06:52.123Z` — the same shape as JS toISOString(),
    /// so event ids (iso|type) look alike from both apps.
    static let withMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
