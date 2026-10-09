import XCTest
@testable import CoachApp

/// Fixture-based checks for the sync merge algorithm (src/db/sync.js
/// port) — the trickiest part of the app to get subtly wrong, since it
/// runs unattended across devices. These mirror the specific rules the
/// JS implementation encodes: newest-updatedAt-wins per session,
/// deletion tombstones beat a live copy, events dedup by (iso|type).
final class GitHubSyncTests: XCTestCase {

    private func session(id: String, date: String, updatedAt: Double, finished: Bool = true, deleted: Bool = false) -> Session {
        Session(id: id, date: date, startedAt: 0, checkin: nil, plan: Plan(), log: [], finished: finished, updatedAt: updatedAt, deleted: deleted)
    }

    // MARK: normalizeBackup

    func testNormalizeBackup_foldsInPlaceTombstoneIntoDeletedIds() {
        var b = Backup()
        b.sessions = [session(id: "2026-01-01#1", date: "2026-01-01", updatedAt: 100, deleted: true)]
        let out = GitHubSync.normalizeBackup(b)
        XCTAssertTrue(out.sessions.isEmpty, "deleted session must not appear in the normalized sessions list")
        XCTAssertEqual(out.deletedIds.map(\.id), ["2026-01-01#1"])
    }

    func testNormalizeBackup_filtersSessionsAlreadyInDeletedIds() {
        var b = Backup()
        b.sessions = [session(id: "s1", date: "2026-01-01", updatedAt: 100)]
        b.deletedIds = [DeletedId(id: "s1", at: 50)]
        let out = GitHubSync.normalizeBackup(b)
        XCTAssertTrue(out.sessions.isEmpty, "a session whose id is already tombstoned must be dropped even without the inline flag")
    }

    func testNormalizeBackup_dropsSessionsWithNoDate() {
        var b = Backup()
        b.sessions = [session(id: "s1", date: "", updatedAt: 100)]
        let out = GitHubSync.normalizeBackup(b)
        XCTAssertTrue(out.sessions.isEmpty)
    }

    // MARK: mergeBackups — session resolution

    func testMergeBackups_newerUpdatedAtWins() {
        var local = Backup()
        local.sessions = [session(id: "s1", date: "2026-01-01", updatedAt: 100, finished: false)]
        var remote = Backup()
        remote.sessions = [session(id: "s1", date: "2026-01-01", updatedAt: 200, finished: true)]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertEqual(merged.sessions.count, 1)
        XCTAssertEqual(merged.sessions.first?.updatedAt, 200)
        XCTAssertTrue(merged.sessions.first?.finished ?? false)
    }

    func testMergeBackups_tieBreaksOnFinishedFlag() {
        // Equal updatedAt (e.g. a race): a finished copy beats an
        // in-progress one rather than being arbitrary.
        var local = Backup()
        local.sessions = [session(id: "s1", date: "2026-01-01", updatedAt: 100, finished: true)]
        var remote = Backup()
        remote.sessions = [session(id: "s1", date: "2026-01-01", updatedAt: 100, finished: false)]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertTrue(merged.sessions.first?.finished ?? false)
    }

    func testMergeBackups_unionsDistinctSessionIds() {
        var local = Backup()
        local.sessions = [session(id: "a", date: "2026-01-01", updatedAt: 100)]
        var remote = Backup()
        remote.sessions = [session(id: "b", date: "2026-01-02", updatedAt: 100)]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertEqual(Set(merged.sessions.map(\.id)), ["a", "b"])
    }

    // MARK: mergeBackups — deletion tombstones

    func testMergeBackups_deletionWinsOverLiveRemoteCopy() {
        // Local deleted a session (tombstone, no session row); remote
        // still has the live row because it hasn't synced since. The
        // deletion must win regardless of how "new" the live copy looks.
        var local = Backup()
        local.deletedIds = [DeletedId(id: "s1", at: 500)]
        var remote = Backup()
        remote.sessions = [session(id: "s1", date: "2026-01-01", updatedAt: 999)]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertTrue(merged.sessions.isEmpty, "a tombstoned id must never resurrect from the other side")
        XCTAssertEqual(merged.deletedIds.map(\.id), ["s1"])
    }

    func testMergeBackups_tombstoneUnionKeepsNewestTimestamp() {
        var local = Backup()
        local.deletedIds = [DeletedId(id: "s1", at: 100)]
        var remote = Backup()
        remote.deletedIds = [DeletedId(id: "s1", at: 900)]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertEqual(merged.deletedIds.first?.at, 900)
    }

    // MARK: mergeBackups — events

    func testMergeBackups_dedupsEventsByIsoAndType() {
        let e = Event(ts: 1, iso: "2026-01-01T00:00:00Z", type: "app_open", data: [:])
        var local = Backup()
        local.events = [e]
        var remote = Backup()
        remote.events = [e]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertEqual(merged.events.count, 1)
    }

    // MARK: mergeBackups — aiSettings / health

    func testMergeBackups_aiSettingsNewestUpdatedAtWins() {
        var local = Backup()
        local.aiSettings = AISettings(profile: "local profile", updatedAt: 100)
        var remote = Backup()
        remote.aiSettings = AISettings(profile: "remote profile", updatedAt: 200)

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertEqual(merged.aiSettings.profile, "remote profile")
    }

    func testMergeBackups_healthRowsUnionByDateFreshestWins() {
        var local = Backup()
        local.health = [HealthRow(date: "2026-01-01", hrv: 40, receivedAt: 100)]
        var remote = Backup()
        remote.health = [HealthRow(date: "2026-01-01", hrv: 55, receivedAt: 200)]

        let merged = GitHubSync.mergeBackups(local, remote)
        XCTAssertEqual(merged.health.first?.hrv, 55)
    }

    // MARK: buildReadme — smoke test, must not crash on empty input

    func testBuildReadme_emptyHistoryDoesNotCrash() {
        let md = GitHubSync.buildReadme([])
        XCTAssertTrue(md.contains("0 sessions"))
    }
}
