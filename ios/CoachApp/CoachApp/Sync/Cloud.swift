import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

/// Cloud Firestore — the live database, shared with the web app (port of
/// src/db/cloud.js; schema + rules: docs/firestore.md).
///
/// Signing in with Google proves an email; allowlist/{email} maps it to
/// one account (a Google account's first sign-in creates its own). That account's documents are mirrored into LocalStore by
/// snapshot listeners (so screens keep reading LocalStore synchronously),
/// and every LocalStore mutation writes through here in the background —
/// Firestore queues writes offline, so logging a set never waits on the
/// network.
final class Cloud {
    static let shared = Cloud()

    struct AccountInfo: Equatable {
        var accountId: String
        var name: String
        var admin: Bool
        var email: String
        /// Signed itself up (not added by the owner): uses its own Gemini key.
        var selfServe = false
    }

    enum CloudError: LocalizedError {
        case blocked(String)
        case noPresenter
        case signInFailed(String)

        var errorDescription: String? {
            switch self {
            case .blocked(let email): return "\(email) has been turned off on COACH. Ask Abhi if that's a mistake."
            case .noPresenter: return "Couldn't show the Google sign-in screen — try again."
            case .signInFailed(let m): return m
            }
        }
    }

    private(set) var account: AccountInfo?
    /// accounts/{id} — name, github { repo, token, lastBackup }, …
    private(set) var accountDoc: [String: JSONValue] = [:]
    /// config/shared — { geminiKey } (invited accounts only)
    private(set) var shared: [String: JSONValue] = [:]
    /// accounts/{id}/state/* other than aiSettings (today, weeklyReview, …)
    private(set) var state: [String: JSONValue] = [:]

    /// Called on the main queue with what changed: "sessions" | "health"
    /// | "state" | "account" | "shared".
    var onChange: ((String) -> Void)?

    /// DebugSeed / previews: no Firebase at all, LocalStore only.
    var offline = false

    private var listeners: [ListenerRegistration] = []
    private var db: Firestore { Firestore.firestore() }

    // ── Setup ────────────────────────────────────────────────────

    private static var configured = false

    static func configure() {
        // a flag, not `FirebaseApp.app() == nil`: asking Firebase before
        // it's configured logs a misleading "not yet configured" warning
        guard !configured else { return }
        configured = true
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    /// Invited accounts share the owner's key; self-serve ones bring their own.
    var geminiKey: String {
        let source = account?.selfServe == true ? accountDoc : shared
        if case .string(let k)? = source["geminiKey"] { return k }
        return ""
    }

    /// The owner (shared key) or a self-serve account (its own) can change it.
    var canSetGeminiKey: Bool { account?.admin == true || account?.selfServe == true }

    var github: [String: JSONValue] {
        if case .object(let g)? = accountDoc["github"] { return g }
        return [:]
    }

    private func path(_ parts: String...) -> String {
        (["accounts", account?.accountId ?? "_"] + parts).joined(separator: "/")
    }

    // ── Auth ─────────────────────────────────────────────────────

    /// The Firebase user restored from the keychain, if any.
    var signedInUser: User? { offline ? nil : Auth.auth().currentUser }

    @MainActor
    func signInWithGoogle() async throws -> User {
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
        else { throw CloudError.noPresenter }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw CloudError.signInFailed("Google didn't return an identity — try again.")
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        return try await Auth.auth().signIn(with: credential).user
    }

    /// Sign out and drop this device's offline copy of the account.
    /// True once every write made on this device has reached the server,
    /// waiting at most `timeout` seconds (false when offline).
    func flushWrites(timeout: Double = 8) async -> Bool {
        guard !offline, account != nil else { return true }
        // not a task group: it would wait for waitForPendingWrites, which
        // never finishes offline — the timeout must really end the wait
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(cont)
            db.waitForPendingWrites { error in once.resume(error == nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { once.resume(false) }
        }
    }

    /// Resumes a continuation exactly once (first of: writes flushed / timeout).
    private final class ResumeOnce {
        private var cont: CheckedContinuation<Bool, Never>?
        init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
        func resume(_ value: Bool) {
            cont?.resume(returning: value)
            cont = nil
        }
    }

    func signOut() async {
        stop()
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        try? await db.terminate()
        try? await db.clearPersistence()
    }

    // ── Session: allowlist → account → live listeners ────────────

    /// First sign-in of an email the owner didn't add: it gets its own
    /// empty account, keyed by the Firebase uid (the only shape the rules
    /// accept — never admin, never another account).
    private func signUp(user: User, email: String) async throws -> [String: Any] {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let name = user.displayName ?? String(email.split(separator: "@").first ?? "")
        let entry: [String: Any] = [
            "accountId": user.uid, "name": name, "admin": false, "selfServe": true, "createdAt": now,
        ]
        let batch = db.batch()
        batch.setData(entry, forDocument: db.collection("allowlist").document(email))
        batch.setData(["name": name, "createdAt": now], forDocument: db.collection("accounts").document(user.uid))
        try await batch.commit()
        return entry
    }

    /// Opens the user's account and resolves once every listener has
    /// delivered its first snapshot (from the offline cache when there's
    /// no network), so the app renders real data at once.
    func start(user: User) async throws -> AccountInfo {
        stop()
        let email = (user.email ?? "").lowercased()
        // throws offline (unless cached) → the login screen's "check your connection"
        let ref = db.collection("allowlist").document(email)
        var snap = try await ref.getDocument()
        // the offline cache can remember "missing": only sign up on the server's word
        if !snap.exists { snap = try await ref.getDocument(source: .server) }
        var data = snap.data() ?? [:]
        if !snap.exists { data = try await signUp(user: user, email: email) }
        guard let accountId = data["accountId"] as? String else {
            throw CloudError.signInFailed("Your account entry is damaged — ask Abhi.")
        }
        if data["blocked"] as? Bool == true { throw CloudError.blocked(email) }
        let info = AccountInfo(
            accountId: accountId,
            name: data["name"] as? String ?? "",
            admin: data["admin"] as? Bool ?? false,
            email: email,
            selfServe: data["selfServe"] as? Bool ?? false
        )
        account = info
        LocalStore.shared.resetMirror()

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let pending = PendingCount(info.selfServe ? 5 : 6) { done.resume() }
            watchDoc(path(), "account", pending) { [weak self] d in self?.accountDoc = d }
            // the shared key is for invited accounts; self-serve ones bring their own
            if !info.selfServe {
                watchDoc("config/shared", "shared", pending) { [weak self] d in self?.shared = d }
            }
            watchCollection(path("sessions"), "sessions", pending) { changes in
                LocalStore.shared.applyRemoteSessions(changes)
            }
            watchCollection(path("health"), "health", pending) { changes in
                LocalStore.shared.applyRemoteHealth(changes)
            }
            watchCollection(path("deletedIds"), "deletedIds", pending) { changes in
                LocalStore.shared.applyRemoteDeletedIds(changes)
            }
            watchCollection(path("state"), "state", pending) { [weak self] changes in
                for (id, value) in changes {
                    if id == "aiSettings" {
                        LocalStore.shared.applyRemoteAISettings(value)
                    } else if case .object(let o)? = value {
                        self?.state[id] = o["value"] ?? .null
                    } else {
                        self?.state[id] = nil
                    }
                }
            }
        }
        return info
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        account = nil
        accountDoc = [:]
        shared = [:]
        state = [:]
    }

    /// Resolves the start() continuation once all first snapshots are in.
    private final class PendingCount {
        private var left: Int
        private let done: () -> Void
        init(_ n: Int, _ done: @escaping () -> Void) { left = n; self.done = done }
        func one() { left -= 1; if left == 0 { done() } }
    }

    private func watchDoc(_ p: String, _ label: String, _ pending: PendingCount, apply: @escaping ([String: JSONValue]) -> Void) {
        var first = true
        listeners.append(db.document(p).addSnapshotListener { [weak self] snap, err in
            if let snap {
                if case .object(let o) = FirestoreCodec.decode(snap.data() ?? [:]) { apply(o) }
            } else if let err {
                print("[COACH] listener \(label) failed: \(err.localizedDescription)")
            }
            if first { first = false; pending.one() }
            self?.onChange?(label)
        })
    }

    /// Delivers (documentId, decoded value or nil when removed) per change.
    private func watchCollection(_ p: String, _ label: String, _ pending: PendingCount, apply: @escaping ([(String, JSONValue?)]) -> Void) {
        var first = true
        listeners.append(db.collection(p).addSnapshotListener { [weak self] snap, err in
            if let snap {
                apply(snap.documentChanges.map { ch in
                    (ch.document.documentID, ch.type == .removed ? nil : FirestoreCodec.decode(ch.document.data()))
                })
            } else if let err {
                print("[COACH] listener \(label) failed: \(err.localizedDescription)")
            }
            if first { first = false; pending.one() }
            self?.onChange?(label)
        })
    }

    #if DEBUG
    /// DebugSeed: a signed-in-looking state with no Firebase behind it.
    func debugActivate(account: AccountInfo, geminiKey: String) {
        offline = true
        self.account = account
        shared = ["geminiKey": .string(geminiKey)]
    }
    #endif

    // ── Writes (background; failures are logged, the next snapshot
    //    puts the mirror back in line) ─────────────────────────────

    private var active: Bool { !offline && account != nil }

    /// Completion for a write. Writes are handed to the SDK synchronously
    /// (not from separate Tasks), so Firestore applies them in exactly the
    /// order they were made — typing "62.5" can't land as "62.".
    private func logged(_ what: String) -> (Error?) -> Void {
        { error in
            if let error { print("[COACH] cloud write failed (\(what)): \(error.localizedDescription)") }
        }
    }

    func putSession(_ s: Session) {
        guard active, let data = try? FirestoreCodec.document(s) else { return }
        let ref = db.document(path("sessions", FirestoreCodec.docId(s.id)))
        ref.setData(data, completion: logged("session"))
    }

    /// Delete for real + permanent marker, atomically.
    func deleteSession(id: String, at: Double) {
        guard active else { return }
        let batch = db.batch()
        batch.setData(["id": id, "at": FirestoreCodec.encode(.number(at))], forDocument: db.document(path("deletedIds", FirestoreCodec.docId(id))))
        batch.deleteDocument(db.document(path("sessions", FirestoreCodec.docId(id))))
        batch.commit(completion: logged("delete session"))
    }

    /// "Clear all history": every session removed AND marked deleted.
    func clearSessions(ids: [String], at: Double) {
        guard active, !ids.isEmpty else { return }
        for chunk in stride(from: 0, to: ids.count, by: 225).map({ Array(ids[$0..<min($0 + 225, ids.count)]) }) {
            let batch = db.batch()
            for id in chunk {
                batch.setData(["id": id, "at": FirestoreCodec.encode(.number(at))], forDocument: db.document(path("deletedIds", FirestoreCodec.docId(id))))
                batch.deleteDocument(db.document(path("sessions", FirestoreCodec.docId(id))))
            }
            batch.commit(completion: logged("clear history"))
        }
    }

    func putHealth(_ row: HealthRow) {
        guard active, let data = try? FirestoreCodec.document(row) else { return }
        let ref = db.document(path("health", FirestoreCodec.docId(row.date)))
        ref.setData(data, completion: logged("health"))
    }

    func putAISettings(_ settings: AISettings) {
        guard active, let data = try? FirestoreCodec.document(settings) else { return }
        let ref = db.document(path("state", "aiSettings"))
        ref.setData(data, completion: logged("aiSettings"))
    }

    func logEvent(_ e: Event) {
        guard active, let data = try? FirestoreCodec.document(e) else { return }
        let ref = db.document(path("events", FirestoreCodec.eventDocId(e)))
        ref.setData(data, completion: logged("event"))
    }

    /// Account state other than aiSettings; nil deletes the key.
    func stateValue(_ key: String) -> JSONValue? { state[key] }

    func setState(_ key: String, _ value: JSONValue?) {
        if offline || account == nil { state[key] = value; return }
        let ref = db.document(path("state", FirestoreCodec.docId(key)))
        state[key] = value
        onChange?("state")
        guard let value else { ref.delete(completion: logged("state \(key)")); return }
        let data: [String: Any] = [
            "value": FirestoreCodec.encode(value),
            "updatedAt": FirestoreCodec.encode(.number((Date().timeIntervalSince1970 * 1000).rounded())),
        ]
        ref.setData(data, completion: logged("state \(key)"))
    }

    func stateKeys() -> [String] { Array(state.keys) }

    /// Patch accounts/{id}.github ({ repo, token, lastBackup }).
    func updateGithub(_ patch: [String: JSONValue]) {
        var g = github
        for (k, v) in patch { g[k] = v }
        accountDoc["github"] = .object(g)
        onChange?("account")
        guard active else { return }
        let data = FirestoreCodec.encode(.object(g))
        let ref = db.document(path())
        ref.updateData(["github": data], completion: logged("github settings"))
    }

    /// Owner only — the rules reject anyone else.
    func setSharedGeminiKey(_ key: String) {
        shared["geminiKey"] = .string(key)
        onChange?("shared")
        guard active, account?.admin == true else { return }
        let ref = db.document("config/shared")
        ref.setData(["geminiKey": key], merge: true, completion: logged("shared key"))
    }

    /// Self-serve accounts: their own Gemini key, on accounts/{id}.
    func setOwnGeminiKey(_ key: String) {
        accountDoc["geminiKey"] = .string(key)
        onChange?("account")
        guard active, account?.selfServe == true else { return }
        db.document(path()).updateData(["geminiKey": key], completion: logged("own key"))
    }

    /// Awaited: the user is told it was sent.
    func sendFeedback(_ text: String) async throws {
        guard active, let account else { throw CloudError.signInFailed("Not signed in.") }
        try await db.collection(path("feedback")).document().setData([
            "text": text, "name": account.name, "email": account.email,
            "at": FirestoreCodec.encode(.number((Date().timeIntervalSince1970 * 1000).rounded())),
        ])
    }

    /// "Import backup": make the account's sessions/health match a
    /// (normalized) backup and add its events + deletion markers — the
    /// web's cloudReplaceData. Sessions the rules would refuse (an older
    /// copy than the stored one, or a deleted id) are skipped, since one
    /// refused write fails its whole batch. Returns how many were skipped.
    func replaceData(with b: Backup) async throws -> Int {
        guard active else { return 0 }
        var ops: [(WriteBatch) -> Void] = []
        let mirror = LocalStore.shared.backup
        let keepIds = Set(b.sessions.map(\.id)), keepDates = Set(b.health.map(\.date))
        for s in mirror.sessions where !keepIds.contains(s.id) {
            let ref = db.document(path("sessions", FirestoreCodec.docId(s.id)))
            ops.append { $0.deleteDocument(ref) }
        }
        for h in mirror.health where !keepDates.contains(h.date) {
            let ref = db.document(path("health", FirestoreCodec.docId(h.date)))
            ops.append { $0.deleteDocument(ref) }
        }
        for d in b.deletedIds {
            let ref = db.document(path("deletedIds", FirestoreCodec.docId(d.id)))
            let data: [String: Any] = ["id": d.id, "at": FirestoreCodec.encode(.number(d.at))]
            ops.append { $0.setData(data, forDocument: ref) }
        }
        let deleted = Set(mirror.deletedIds.map(\.id) + b.deletedIds.map(\.id))
        var skipped = 0
        for s in b.sessions {
            if deleted.contains(s.id) || (mirror.sessions.first { $0.id == s.id }?.updatedAt ?? 0) > s.updatedAt {
                skipped += 1
                continue
            }
            let ref = db.document(path("sessions", FirestoreCodec.docId(s.id)))
            if let data = try? FirestoreCodec.document(s) { ops.append { $0.setData(data, forDocument: ref) } }
        }
        for h in b.health {
            let ref = db.document(path("health", FirestoreCodec.docId(h.date)))
            if let data = try? FirestoreCodec.document(h) { ops.append { $0.setData(data, forDocument: ref) } }
        }
        for e in b.events {
            let ref = db.document(path("events", FirestoreCodec.eventDocId(e)))
            if let data = try? FirestoreCodec.document(e) { ops.append { $0.setData(data, forDocument: ref) } }
        }
        for start in stride(from: 0, to: ops.count, by: 450) {
            let batch = db.batch()
            ops[start..<min(start + 450, ops.count)].forEach { $0(batch) }
            try await batch.commit()
        }
        return skipped
    }

    // ── On-demand reads ──────────────────────────────────────────

    /// The whole event log (write-only otherwise) — for the GitHub backup.
    func allEvents() async throws -> [Event] {
        guard active else { return LocalStore.shared.backup.events }
        let qs = try await db.collection(path("events")).getDocuments()
        return qs.documents.compactMap { try? FirestoreCodec.model(Event.self, from: $0.data()) }
    }

    func countEvents() async -> Int {
        guard active else { return LocalStore.shared.backup.events.count }
        let agg = try? await db.collection(path("events")).count.getAggregation(source: .server)
        return agg?.count.intValue ?? 0
    }
}
