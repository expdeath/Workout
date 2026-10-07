import Foundation

/// GitHub backup + Watch inbox — port of src/db/sync.js.
///
/// Firestore (Cloud.swift) is the live database and syncs devices on its
/// own. GitHub keeps two jobs:
///   1. Backup: the full account as coach-backup.json (same shape as
///      always) + a human-readable README log, in the account's private
///      data repo. Pushed when data changed (≥10 min apart) or daily.
///   2. Watch inbox: the Gym Check-in Shortcut PUTs files into
///      health-inbox/; every sync drains them into Firestore.
/// The repo + a fine-grained token (Contents read/write on that repo
/// only) live in accounts/{id}.github, shared by every device of the
/// account — and by the web app.
enum GitHubSync {
    struct Config {
        var token: String
        var repo: String
    }

    private static let api = "https://api.github.com"
    private static let file = "coach-backup.json"
    private static let readmePath = "README.md"
    private static let branch = "main"
    private static let inbox = "health-inbox"
    private static let minGap: TimeInterval = 10 * 60
    private static let day: TimeInterval = 24 * 60 * 60

    // ── Config (accounts/{id}.github) ────────────────────────────

    static func config() -> Config {
        let g = Cloud.shared.github
        func str(_ k: String) -> String { if case .string(let s)? = g[k] { return s }; return "" }
        return Config(token: str("token"), repo: str("repo"))
    }

    static func setConfig(token: String, repo: String) {
        let cleanRepo = repo
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        Cloud.shared.updateGithub([
            "token": .string(token.trimmingCharacters(in: .whitespacesAndNewlines)),
            "repo": .string(cleanRepo),
        ])
    }

    /// Last backup attempt — shared by every device of the account.
    struct LastSyncInfo {
        var at: String
        var status: String
        var sessions: Int?
        var message: String?
        var fingerprint: String?
    }

    static func lastSync() -> LastSyncInfo? {
        guard case .object(let o)? = Cloud.shared.github["lastBackup"] else { return nil }
        func str(_ k: String) -> String? { if case .string(let s)? = o[k] { return s }; return nil }
        var sessions: Int? = nil
        if case .number(let n)? = o["sessions"] { sessions = Int(n) }
        return LastSyncInfo(at: str("at") ?? "", status: str("status") ?? "", sessions: sessions, message: str("message"), fingerprint: str("fingerprint"))
    }

    private static func setLastSync(_ info: [String: JSONValue]) {
        var cur: [String: JSONValue] = [:]
        if case .object(let o)? = Cloud.shared.github["lastBackup"] { cur = o }
        cur["at"] = .string(ISO8601DateFormatter.withMillis.string(from: Date()))
        for (k, v) in info { cur[k] = v }
        Cloud.shared.updateGithub(["lastBackup": .object(cur)])
    }

    struct LastInboxInfo: Codable {
        var at: Double
        var files: Int
    }

    /// Per-device diagnostic (like the web app's coach:last-inbox).
    static func lastInbox() -> LastInboxInfo? {
        Defaults.codable(LastInboxInfo.self, "last-inbox")
    }

    enum SyncError: LocalizedError {
        case tokenRejected
        case conflict
        case http(Int, String)
        case message(String)

        var errorDescription: String? {
            switch self {
            case .tokenRejected:
                return "GitHub token rejected — check it in Settings (needs Contents read/write on your data repo)."
            case .conflict:
                return "sync conflict"
            case .http(let status, let body):
                return "GitHub error \(status): \(body)"
            case .message(let m):
                return m
            }
        }
    }

    // ── GitHub API helpers ──────────────────────────────────────

    private static func request(_ cfg: Config, path: String, method: String = "GET", body: Data? = nil, extraHeaders: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: URL(string: api + path)!)
        req.httpMethod = method
        req.httpBody = body
        // GitHub's API sends max-age=60; a cached read here means a device
        // can miss another device's push for a minute and then fail its own
        // push with a version conflict. Always hit the network.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    private struct GitTree: Codable { var tree: [Entry]?; struct Entry: Codable { var path: String; var sha: String } }
    private struct ContentEntry: Codable { var name: String; var path: String; var sha: String; var type: String }
    private struct PutBody: Encodable {
        var message: String
        var content: String
        var branch: String
        var sha: String?
    }
    private struct DeleteBody: Encodable {
        var message: String
        var sha: String
        var branch: String
    }

    /// Blob shas of our files on the remote (backup, readme), or nils.
    private static func remoteShas(_ cfg: Config) async throws -> (backup: String?, readme: String?) {
        let (data, resp) = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/git/trees/\(branch)"))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 || status == 409 { return (nil, nil) }
        guard status == 200 else { throw SyncError.http(status, String(data: data, encoding: .utf8) ?? "") }
        let tree = try JSONDecoder().decode(GitTree.self, from: data)
        let shaOf = { (p: String) in tree.tree?.first(where: { $0.path == p })?.sha }
        return (shaOf(file), shaOf(readmePath))
    }

    private static func commitMessage(_ backup: Backup) -> String {
        let active = backup.sessions.filter { !$0.deleted }
        guard let last = active.last else { return "sync: no sessions yet" }
        return "sync: \(active.count) sessions · latest \(last.date) \(last.plan.sessionType)".trimmingCharacters(in: .whitespaces)
    }

    private static func b64encode(_ str: String) -> String {
        Data(str.utf8).base64EncodedString()
    }

    /// Overwrite coach-backup.json — Firestore is the truth, so no merge.
    /// A sha race with another device of the account just retries.
    private static func pushRemote(_ cfg: Config, _ backup: Backup) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = String(data: try encoder.encode(backup), encoding: .utf8) ?? "{}"
        for _ in 0..<3 {
            let sha = try await remoteShas(cfg).backup
            let body = try JSONEncoder().encode(PutBody(message: commitMessage(backup), content: b64encode(json), branch: branch, sha: sha))
            let (data, resp) = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(file)", method: "PUT", body: body))
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 || status == 201 { return }
            if status == 401 || status == 403 { throw SyncError.tokenRejected }
            guard status == 409 || status == 422 else { throw SyncError.http(status, String(data: data, encoding: .utf8) ?? "") }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        throw SyncError.message("Backup conflict — another device is backing up right now. It will retry later.")
    }

    // ── Repo README: human-readable training log for GitHub ────

    static func buildReadme(_ sessions: [Session]) -> String {
        let active = sessions.filter { !$0.deleted && !$0.date.isEmpty }
        let (thisWeek, streak) = Stats.weekStats(active)
        let rows = active.suffix(20).reversed().map { s -> String in
            let vol = Stats.sessionVolume(s)
            let best = s.plan.exercises.enumerated().compactMap { (i, ex) -> String? in
                let sets = (i < s.log.count ? s.log[i] : []).filter { $0.isLogged }
                guard let top = sets.max(by: { (Double($0.weight) ?? 0) < (Double($1.weight) ?? 0) }) else { return nil }
                return "\(ex.name) \(top.weight.isEmpty ? "?" : top.weight)×\(top.reps.isEmpty ? "?" : top.reps)"
            }.joined(separator: " · ")
            let volStr = vol > 0 ? "\(vol) kg" : "—"
            return "| \(Helpers.fmtDate(s.date)) | \(s.plan.sessionType.isEmpty ? "?" : s.plan.sessionType) | \(s.fin?.rpe.description ?? "—") | \(volStr) | \(best.isEmpty ? "—" : best) |"
        }.joined(separator: "\n")

        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(16).replacingOccurrences(of: "T", with: " ")
        return """
        # 🏋️ COACH — Training Data

        Auto-synced by the [COACH app](https://expdeath.github.io/Workout/). Don't edit by hand — the app owns this repo.

        **\(active.count) sessions** · **\(thisWeek) this week** · **\(streak)-week streak** (≥3/week)

        ## Recent sessions

        | Date | Session | RPE | Volume | Top sets |
        |---|---|---|---|---|
        \(rows.isEmpty ? "| — | — | — | — | — |" : rows)

        <sub>Full data (including the event log) lives in [`coach-backup.json`](./coach-backup.json). Updated \(stamp) UTC.</sub>

        """
    }

    private static func pushReadme(_ cfg: Config, _ sessions: [Session]) async {
        do {
            let sha = try await remoteShas(cfg).readme
            let body = try JSONEncoder().encode(PutBody(message: "docs: update training log", content: b64encode(buildReadme(sessions)), branch: branch, sha: sha))
            _ = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(readmePath)", method: "PUT", body: body))
        } catch {
            // cosmetic — never fatal
        }
    }

    // ── Beta feedback (accounts/{id}/feedback in Firestore) ──────

    static func sendFeedback(_ text: String) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw SyncError.message("Write something first.") }
        do {
            try await Cloud.shared.sendFeedback(String(body.prefix(2000)))
        } catch {
            throw SyncError.message("Couldn't send — check your connection and try again.")
        }
    }

    // ── Health inbox ─────────────────────────────────────────────
    // The Watch shortcut PUTs one small file per run into health-inbox/.
    // Every sync drains it: parse → merge into the health rows → delete
    // the file. Produces the same rows as the web app's drain (which
    // fills every field parseHealthNumbers finds), so it doesn't matter
    // which app gets to a file first.

    private struct InboxNums { var hrv, rhr, steps, sleepH, weightKg: Double? }

    /// File body → (text, structured numbers if the payload was JSON
    /// with recognizable fields). Free-text regex parsing of the kind
    /// stats.js's parseHealthNumbers does lands in Phase 4 — for now an
    /// unstructured payload is kept verbatim in the row's `raw` field so
    /// no data is lost, just not yet split into typed fields.
    private static func parseInboxFile(_ body: String) -> (text: String, nums: InboxNums?) {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{"), let data = t.data(using: .utf8) else { return (t, nil) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (t, nil) }
        if let health = obj["health"] as? String { return (health, nil) }
        var nums = InboxNums()
        var any = false
        func num(_ key: String) -> Double? {
            if let n = obj[key] as? Double, n > 0 { return n }
            if let n = obj[key] as? Int, n > 0 { return Double(n) }
            return nil
        }
        if let v = num("hrv") { nums.hrv = v; any = true }
        if let v = num("rhr") { nums.rhr = v; any = true }
        if let v = num("steps") { nums.steps = v; any = true }
        if let v = num("sleepH") { nums.sleepH = v; any = true }
        if let v = num("weightKg") { nums.weightKg = v; any = true }
        return (t, any ? nums : nil)
    }

    /// Drains health-inbox/ into Firestore, then deletes each file from
    /// the repo. Per-file failures are skipped (retried next sync).
    /// Returns the number of files ingested.
    @discardableResult
    static func consumeHealthInbox(_ cfg: Config = config()) async throws -> Int {
        guard !cfg.token.isEmpty, !cfg.repo.isEmpty else { return 0 }
        let (listData, listResp) = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(inbox)?ref=\(branch)"))
        let listStatus = (listResp as? HTTPURLResponse)?.statusCode ?? 0
        if listStatus == 404 { return 0 } // no inbox folder yet
        guard listStatus == 200 else { throw SyncError.http(listStatus, String(data: listData, encoding: .utf8) ?? "") }
        guard let files = try? JSONDecoder().decode([ContentEntry].self, from: listData) else { return 0 }

        var ingested = 0
        for f in files.filter({ $0.type == "file" }).prefix(30) {
            guard let encodedName = f.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            do {
                let rawReq = request(cfg, path: "/repos/\(cfg.repo)/contents/\(inbox)/\(encodedName)?ref=\(branch)", extraHeaders: ["Accept": "application/vnd.github.raw+json"])
                let (rawData, rawResp) = try await URLSession.shared.data(for: rawReq)
                guard ((rawResp as? HTTPURLResponse)?.statusCode ?? 0) == 200 else { continue }
                ingestInboxFile(name: f.name, body: String(data: rawData, encoding: .utf8) ?? "")
                let delBody = try JSONEncoder().encode(DeleteBody(message: "chore: ingest \(f.name)", sha: f.sha, branch: branch))
                _ = try? await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(inbox)/\(encodedName)", method: "DELETE", body: delBody))
                ingested += 1
            } catch {
                continue // retried next sync
            }
        }
        if ingested > 0 {
            Defaults.setCodable(LastInboxInfo(at: Date().timeIntervalSince1970 * 1000, files: ingested), for: "last-inbox")
        }
        return ingested
    }

    /// One inbox file → today's check-in text (if it's today's) + the
    /// day's health row. Internal for tests.
    static func ingestInboxFile(name: String, body: String) {
        let (text, nums) = parseInboxFile(body)
        let date = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression).map { String(name[$0]) } ?? Helpers.todayStr()
        let asText: String
        if let nums {
            asText = [
                nums.hrv.map { "HRV \(fmtNum($0)) ms" },
                nums.rhr.map { "RHR \(fmtNum($0))" },
                nums.sleepH.map { "Sleep \(fmtNum($0))h" },
                nums.weightKg.map { "Weight \(fmtNum($0))kg" },
                nums.steps.map { "Steps \(fmtNum($0))" },
            ].compactMap { $0 }.joined(separator: " · ")
        } else {
            asText = text
        }
        guard !asText.isEmpty else { return }
        // today's raw text pre-fills the check-in (healthText-<date>, as on the web)
        if date == Helpers.todayStr() { Cloud.shared.setState("healthText-\(date)", .string(String(asText.prefix(2000)))) }
        let n = Stats.parseHealthNumbers(asText)
        var row = HealthRow(date: date, hrv: n.hrv, rhr: n.rhr, steps: n.steps, sleepH: n.sleepH,
                            respRate: n.respRate, wristC: n.wristC, vo2max: n.vo2max, kcal: n.kcal,
                            exerciseMin: n.exerciseMin, distKm: n.distKm, spo2: n.spo2, raw: String(asText.prefix(300)))
        // structured payloads may carry fields the text parser doesn't (weightKg)
        if let nums {
            row.hrv = nums.hrv ?? row.hrv; row.rhr = nums.rhr ?? row.rhr; row.steps = nums.steps ?? row.steps
            row.sleepH = nums.sleepH ?? row.sleepH; row.weightKg = nums.weightKg
        }
        LocalStore.shared.mergeHealth(row)
    }

    /// JS-style number text: 48 not 48.0, 7.5 stays 7.5.
    private static func fmtNum(_ n: Double) -> String {
        n.rounded() == n ? String(Int64(n)) : String(n)
    }

    // ── Merge ────────────────────────────────────────────────────

    private static func pickSession(_ local: Session?, _ remote: Session?) -> Session? {
        guard let remote else { return local }
        guard let local else { return remote }
        if local.updatedAt != remote.updatedAt { return local.updatedAt > remote.updatedAt ? local : remote }
        if local.finished != remote.finished { return local.finished ? local : remote }
        return local
    }

    private static func eventKey(_ e: Event) -> String { "\(e.iso)|\(e.type)" }

    static func mergeBackups(_ local: Backup, _ remote: Backup?) -> Backup {
        guard let remote else { return normalizeBackup(local) }

        var byId: [String: Session] = [:]
        for s in remote.sessions { byId[s.id] = s }
        for s in local.sessions {
            byId[s.id] = pickSession(s, byId[s.id])
        }

        var delById: [String: Double] = [:]
        for d in local.deletedIds + remote.deletedIds where d.at > (delById[d.id] ?? 0) {
            delById[d.id] = d.at
        }
        let deletedIds = delById.map { DeletedId(id: $0.key, at: $0.value) }

        var seen = Set<String>()
        var events: [Event] = []
        for e in local.events + remote.events {
            let key = eventKey(e)
            if seen.contains(key) { continue }
            seen.insert(key)
            events.append(e)
        }

        let aiSettings = remote.aiSettings.updatedAt > local.aiSettings.updatedAt ? remote.aiSettings : local.aiSettings

        var byDate: [String: HealthRow] = [:]
        for h in remote.health { byDate[h.date] = h }
        for h in local.health {
            let r = byDate[h.date]
            byDate[h.date] = (r == nil || (h.receivedAt ?? 0) >= (r!.receivedAt ?? 0)) ? h : r
        }

        var merged = local
        merged.sessions = Array(byId.values)
        merged.events = events
        merged.health = Array(byDate.values)
        merged.aiSettings = aiSettings
        merged.deletedIds = deletedIds
        return normalizeBackup(merged)
    }

    /// Deterministic shape so backups can be compared reliably.
    static func normalizeBackup(_ b: Backup) -> Backup {
        var dels: [String: Double] = [:]
        for d in b.deletedIds { dels[d.id] = d.at }
        var sessions: [Session] = []
        for s in b.sessions {
            guard !s.date.isEmpty else { continue }
            if s.deleted {
                if dels[s.id] == nil { dels[s.id] = s.updatedAt > 0 ? s.updatedAt : Date().timeIntervalSince1970 * 1000 }
                continue
            }
            if dels[s.id] == nil { sessions.append(s) }
        }
        var out = Backup()
        out.app = "coach"
        out.version = b.version > 0 ? b.version : 1
        out.aiSettings = b.aiSettings
        out.deletedIds = dels.map { DeletedId(id: $0.key, at: $0.value) }.sorted { $0.id < $1.id }
        out.health = b.health.sorted { $0.date < $1.date }
        out.sessions = sessions.sorted { ($0.date + $0.id) < ($1.date + $1.id) }
        out.events = b.events.sorted { eventKey($0) < eventKey($1) }
        return out
    }

    // ── Sync ─────────────────────────────────────────────────────

    enum Status { case unconfigured, ok }
    struct Result {
        var status: Status
        var changedLocal: Bool
        var sessions: Int
        var inboxFiles: Int = 0
        var skipped = false
    }

    /// Cheap "did anything change since the last backup" check — the
    /// same string the web app computes, so the apps agree on it.
    static func fingerprint() -> String {
        let b = LocalStore.shared.backup
        let newest = b.sessions.map(\.updatedAt).max() ?? 0
        return "\(b.sessions.count):\(Int64(max(0, newest))):\(b.deletedIds.count)"
    }

    /// Drain the Watch inbox into Firestore, then back the account up to
    /// GitHub if it's due. `force` backs up now.
    static func syncNow(force: Bool = false) async throws -> Result {
        let cfg = config()
        let sessions = LocalStore.shared.backup.sessions.count
        guard Cloud.shared.account != nil, !cfg.token.isEmpty, !cfg.repo.isEmpty else {
            return Result(status: .unconfigured, changedLocal: false, sessions: sessions)
        }

        // never fatal — a broken inbox must not block the backup
        let inboxFiles = (try? await consumeHealthInbox(cfg)) ?? 0

        let last = lastSync()
        let lastAt = last.flatMap { ISO8601DateFormatter.withMillis.date(from: $0.at) ?? ISO8601DateFormatter().date(from: $0.at) } ?? .distantPast
        let since = Date().timeIntervalSince(lastAt)
        let fp = fingerprint()
        let due = force || last?.status != "ok" || since > day || (fp != last?.fingerprint && since > minGap)
        guard due else {
            return Result(status: .ok, changedLocal: inboxFiles > 0, sessions: sessions, inboxFiles: inboxFiles, skipped: true)
        }

        do {
            var b = LocalStore.shared.backup
            b.events = try await Cloud.shared.allEvents()
            let backup = normalizeBackup(b)
            try await pushRemote(cfg, backup)
            await pushReadme(cfg, backup.sessions)
            setLastSync(["status": .string("ok"), "sessions": .number(Double(backup.sessions.count)), "fingerprint": .string(fp), "message": .null])
            return Result(status: .ok, changedLocal: inboxFiles > 0, sessions: backup.sessions.count, inboxFiles: inboxFiles)
        } catch {
            setLastSync(["status": .string("error"), "message": .string(error.localizedDescription)])
            throw error
        }
    }
}
