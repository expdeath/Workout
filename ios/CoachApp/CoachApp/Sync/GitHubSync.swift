import Foundation

/// GitHub-backed cloud sync — ports src/db/sync.js function-for-function.
/// The full backup (sessions + event log) lives as one JSON file in a
/// private repo the user owns. Sync = pull remote, merge with local
/// (union; newer session wins per id), write back whichever side is
/// stale. Auth: the same fine-grained PAT the web app uses, kept in
/// Keychain here instead of localStorage.
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

    // ── Config ───────────────────────────────────────────────────

    static func config() -> Config {
        Config(token: Keychain.githubToken, repo: Defaults.string("gh-repo") ?? "")
    }

    static func setConfig(token: String, repo: String) {
        Keychain.githubToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRepo = repo
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        Defaults.set(cleanRepo, for: "gh-repo")
    }

    struct LastSyncInfo: Codable {
        var at: String
        var status: String
        var sessions: Int?
        var message: String?
    }

    static func lastSync() -> LastSyncInfo? {
        Defaults.codable(LastSyncInfo.self, "last-sync")
    }

    private static func setLastSync(status: String, sessions: Int? = nil, message: String? = nil) {
        Defaults.setCodable(
            LastSyncInfo(at: ISO8601DateFormatter().string(from: Date()), status: status, sessions: sessions, message: message),
            for: "last-sync"
        )
    }

    struct LastInboxInfo: Codable {
        var at: Double
        var files: Int
    }

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

    /// Download + parse the remote backup. Raw media type dodges the 1MB JSON cap.
    private static func fetchRemote(_ cfg: Config) async throws -> Backup? {
        let req = request(cfg, path: "/repos/\(cfg.repo)/contents/\(file)?ref=\(branch)", extraHeaders: ["Accept": "application/vnd.github.raw+json"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        if status == 401 || status == 403 { throw SyncError.tokenRejected }
        guard status == 200 else { throw SyncError.http(status, String(data: data, encoding: .utf8) ?? "") }
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            throw SyncError.message("Remote backup file is not valid JSON.")
        }
        return backup
    }

    private static func commitMessage(_ backup: Backup) -> String {
        let active = backup.sessions.filter { !$0.deleted }
        guard let last = active.last else { return "sync: no sessions yet" }
        return "sync: \(active.count) sessions · latest \(last.date) \(last.plan.sessionType)".trimmingCharacters(in: .whitespaces)
    }

    private static func b64encode(_ str: String) -> String {
        Data(str.utf8).base64EncodedString()
    }

    private static func pushRemote(_ cfg: Config, _ backup: Backup, sha: String?) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = String(data: try encoder.encode(backup), encoding: .utf8) ?? "{}"
        let body = try JSONEncoder().encode(PutBody(message: commitMessage(backup), content: b64encode(json), branch: branch, sha: sha))
        let (data, resp) = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(file)", method: "PUT", body: body))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409 || status == 422 { throw SyncError.conflict }
        if status == 401 || status == 403 { throw SyncError.tokenRejected }
        guard status == 200 || status == 201 else { throw SyncError.http(status, String(data: data, encoding: .utf8) ?? "") }
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

    private static func pushReadme(_ cfg: Config, _ sessions: [Session], sha: String?) async {
        do {
            let body = try JSONEncoder().encode(PutBody(message: "docs: update training log", content: b64encode(buildReadme(sessions)), branch: branch, sha: sha))
            _ = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(readmePath)", method: "PUT", body: body))
        } catch {
            // cosmetic — never fatal
        }
    }

    // ── Beta feedback ────────────────────────────────────────────

    static func sendFeedback(_ text: String, name: String = "") async throws {
        let cfg = config()
        guard !cfg.token.isEmpty, !cfg.repo.isEmpty else { throw SyncError.message("Sync is not set up.") }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw SyncError.message("Write something first.") }
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(16).replacingOccurrences(of: ":", with: "")
        let path = "feedback/\(stamp).md"
        let dateOnly = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let md = "# Feedback — \(name.isEmpty ? "user" : name) — \(dateOnly)\n\n\(body)\n"
        let putBody = try JSONEncoder().encode(PutBody(message: "feedback: \(stamp)", content: b64encode(md), branch: branch, sha: nil))
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SyncError.message("Invalid feedback path.")
        }
        let (data, resp) = try await URLSession.shared.data(for: request(cfg, path: "/repos/\(cfg.repo)/contents/\(encodedPath)", method: "PUT", body: putBody))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            throw SyncError.message("Couldn't send (GitHub \(status)) — try again later.\n\(String(data: data, encoding: .utf8) ?? "")")
        }
    }

    // ── Health inbox ─────────────────────────────────────────────
    // The Watch shortcut PUTs one small file per run into health-inbox/.
    // Every sync drains the inbox: parse → merge into the health store →
    // delete the file.

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

    /// Drains health-inbox/: merges every file into the local health
    /// store, then deletes it from the repo. Per-file failures are
    /// skipped (retried next sync). Returns the number of files ingested.
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
                let bodyText = String(data: rawData, encoding: .utf8) ?? ""
                let (text, nums) = parseInboxFile(bodyText)
                let dateMatch = f.name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression)
                let date = dateMatch.map { String(f.name[$0]) } ?? Helpers.todayStr()
                let asText: String
                if let nums {
                    asText = [
                        nums.hrv.map { "HRV \(Int($0)) ms" },
                        nums.rhr.map { "RHR \(Int($0))" },
                        nums.sleepH.map { "Sleep \($0)h" },
                        nums.weightKg.map { "Weight \($0)kg" },
                        nums.steps.map { "Steps \(Int($0))" },
                    ].compactMap { $0 }.joined(separator: " · ")
                } else {
                    asText = text
                }
                if !asText.isEmpty {
                    var row = HealthRow(date: date)
                    if let nums {
                        row.hrv = nums.hrv; row.rhr = nums.rhr; row.steps = nums.steps
                        row.sleepH = nums.sleepH; row.weightKg = nums.weightKg
                    }
                    row.raw = String(asText.prefix(300))
                    LocalStore.shared.mergeHealth(row)
                }
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

    enum Status { case unconfigured, ok, pushed }
    struct Result {
        var status: Status
        var changedLocal: Bool
        var sessions: Int
        var inboxFiles: Int = 0
    }

    /// Pull remote, merge with local, write back whichever side is stale.
    /// With replaceRemote: overwrite the cloud with local state (used
    /// after "Clear all history", where a merge would resurrect deleted
    /// data).
    static func syncNow(replaceRemote: Bool = false) async throws -> Result {
        let cfg = config()
        guard !cfg.token.isEmpty, !cfg.repo.isEmpty else { return Result(status: .unconfigured, changedLocal: false, sessions: 0) }

        var inboxFiles = 0
        inboxFiles = (try? await consumeHealthInbox(cfg)) ?? 0

        let local = normalizeBackup(LocalStore.shared.backup)

        if replaceRemote {
            let shas = try await remoteShas(cfg)
            try await pushRemote(cfg, local, sha: shas.backup)
            let shas2 = try await remoteShas(cfg)
            await pushReadme(cfg, local.sessions, sha: shas2.readme)
            setLastSync(status: "ok", sessions: local.sessions.count)
            return Result(status: .pushed, changedLocal: false, sessions: local.sessions.count)
        }

        func doPass() async throws -> Result {
            let remote = try await fetchRemote(cfg)
            let remoteNorm = remote.map(normalizeBackup)
            let merged = mergeBackups(local, remoteNorm)
            let changedLocal = merged != local
            if changedLocal { LocalStore.shared.replaceAll(merged) }
            if remote == nil || merged != remoteNorm {
                let shas = try await remoteShas(cfg)
                try await pushRemote(cfg, merged, sha: shas.backup)
                let sessionsChanged = remoteNorm == nil || merged.sessions != remoteNorm!.sessions
                if sessionsChanged || shas.readme == nil {
                    let shas2 = try await remoteShas(cfg)
                    await pushReadme(cfg, merged.sessions, sha: shas2.readme)
                }
            }
            return Result(status: .ok, changedLocal: changedLocal || inboxFiles > 0, sessions: merged.sessions.count, inboxFiles: inboxFiles)
        }

        do {
            let result = try await doPass()
            setLastSync(status: "ok", sessions: result.sessions)
            return result
        } catch SyncError.conflict {
            // Someone else pushed between our fetch and put — brief pause, once more
            try? await Task.sleep(nanoseconds: 800_000_000)
            do {
                let result = try await doPass()
                setLastSync(status: "ok", sessions: result.sessions)
                return result
            } catch SyncError.conflict {
                let msg = "Sync conflict — another device is syncing right now. It will resolve on the next sync."
                setLastSync(status: "error", message: msg)
                throw SyncError.message(msg)
            } catch {
                setLastSync(status: "error", message: error.localizedDescription)
                throw error
            }
        } catch {
            setLastSync(status: "error", message: error.localizedDescription)
            throw error
        }
    }
}
