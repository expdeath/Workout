import Foundation

/// Local persistence for the full app state. The web app spreads this
/// across IndexedDB stores (sessions/events/health) plus assorted
/// localStorage keys; here it's one Codable `Backup` blob written to a
/// JSON file, since that's already the exact shape synced to GitHub
/// (src/db/sync.js exportAll/replaceAll) — no separate on-device schema
/// to keep in sync with the cloud one.
@Observable
final class LocalStore {
    static let shared = LocalStore()

    private(set) var backup: Backup

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoachApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("backup.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Backup.self, from: data) {
            backup = decoded
        } else {
            backup = Backup()
        }
    }

    /// Overwrite the in-memory state and persist it — used after a sync
    /// merge (Phase 2) or a backup import (Phase 5). Mirrors replaceAll()
    /// in src/db/db.js.
    func replaceAll(_ newBackup: Backup) {
        backup = newBackup
        save()
    }

    /// Mirrors clearSessions() in src/db/db.js — used by "Clear all
    /// history" in Settings, which then overwrites the cloud too (a
    /// merge would otherwise resurrect the deleted data).
    func clearSessions() {
        backup.sessions = []
        save()
    }

    func upsert(session: Session) {
        if let i = backup.sessions.firstIndex(where: { $0.id == session.id }) {
            backup.sessions[i] = session
        } else {
            backup.sessions.append(session)
        }
        save()
    }

    /// Removes the session for real and records a tombstone, so the
    /// deletion propagates via sync instead of the row resurrecting on
    /// another device (mirrors hardDeleteSession() in src/db/db.js).
    func hardDelete(sessionId: String) {
        backup.sessions.removeAll { $0.id == sessionId }
        backup.deletedIds.removeAll { $0.id == sessionId }
        backup.deletedIds.append(DeletedId(id: sessionId, at: Date().timeIntervalSince1970 * 1000))
        save()
    }

    func logEvent(type: String, data: [String: JSONValue] = [:]) {
        let now = Date()
        backup.events.append(Event(ts: now.timeIntervalSince1970 * 1000, iso: ISO8601DateFormatter().string(from: now), type: type, data: data))
        save()
    }

    /// Mirrors setAISettings() in src/utils/storage.js — shallow-merges
    /// the patch and stamps updatedAt so cloud sync's newest-wins rule
    /// (src/db/sync.js) picks the right copy.
    func updateAISettings(_ patch: (inout AISettings) -> Void) {
        patch(&backup.aiSettings)
        backup.aiSettings.updatedAt = Date().timeIntervalSince1970 * 1000
        save()
    }

    func mergeHealth(_ patch: HealthRow) {
        if let i = backup.health.firstIndex(where: { $0.date == patch.date }) {
            var existing = backup.health[i]
            if let v = patch.hrv { existing.hrv = v }
            if let v = patch.rhr { existing.rhr = v }
            if let v = patch.steps { existing.steps = v }
            if let v = patch.sleepH { existing.sleepH = v }
            if let v = patch.weightKg { existing.weightKg = v }
            if let v = patch.respRate { existing.respRate = v }
            if let v = patch.wristC { existing.wristC = v }
            if let v = patch.vo2max { existing.vo2max = v }
            if let v = patch.raw { existing.raw = v }
            existing.receivedAt = patch.receivedAt ?? Date().timeIntervalSince1970 * 1000
            backup.health[i] = existing
        } else {
            var row = patch
            row.receivedAt = row.receivedAt ?? Date().timeIntervalSince1970 * 1000
            backup.health.append(row)
        }
        save()
    }

    /// Wipes local data back to empty — used by Account.wipeLocal() on
    /// sign-out / account switch. Cloud copies are untouched.
    func wipe() {
        backup = Backup()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(backup) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
