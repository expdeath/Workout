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
/// one account. That account's documents are mirrored into LocalStore by
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
    }

    enum CloudError: LocalizedError {
        case notInvited(String)
        case noPresenter
        case signInFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInvited(let email): return "\(email) isn't on the COACH invite list. Ask Abhi to add it."
            case .noPresenter: return "Couldn't show the Google sign-in screen — try again."
            case .signInFailed(let m): return m
            }
        }
    }

    private(set) var account: AccountInfo?
    /// accounts/{id} — name, github { repo, token, lastBackup }, …
    private(set) var accountDoc: [String: JSONValue] = [:]
    /// config/shared — { geminiKey }
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

    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    var geminiKey: String {
        if case .string(let k)? = shared["geminiKey"] { return k }
        return ""
    }

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
    func signOut() async {
        stop()
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        try? await db.terminate()
        try? await db.clearPersistence()
    }

    // ── Session: allowlist → account → live listeners ────────────

    /// Opens the user's account and resolves once every listener has
    /// delivered its first snapshot (from the offline cache when there's
    /// no network), so the app renders real data at once.
    func start(user: User) async throws -> AccountInfo {
        stop()
        let email = (user.email ?? "").lowercased()
        let entry = try? await db.collection("allowlist").document(email).getDocument()
        guard let entry, entry.exists, let data = entry.data(), let accountId = data["accountId"] as? String else {
            throw CloudError.notInvited(email)
        }
        let info = AccountInfo(
            accountId: accountId,
            name: data["name"] as? String ?? "",
            admin: data["admin"] as? Bool ?? false,
            email: email
        )
        account = info
        LocalStore.shared.resetMirror()

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let pending = PendingCount(6) { done.resume() }
            watchDoc(path(), "account", pending) { [weak self] d in self?.accountDoc = d }
            watchDoc("config/shared", "shared", pending) { [weak self] d in self?.shared = d }
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

    private func write(_ what: String, _ op: @escaping () async throws -> Void) {
        guard active else { return }
        Task {
            do { try await op() } catch { print("[COACH] cloud write failed (\(what)): \(error.localizedDescription)") }
        }
    }

    func putSession(_ s: Session) {
        guard active, let data = try? FirestoreCodec.document(s) else { return }
        let ref = db.document(path("sessions", FirestoreCodec.docId(s.id)))
        write("session") { try await ref.setData(data) }
    }

    /// Delete for real + permanent marker, atomically.
    func deleteSession(id: String, at: Double) {
        guard active else { return }
        let batch = db.batch()
        batch.setData(["id": id, "at": FirestoreCodec.encode(.number(at))], forDocument: db.document(path("deletedIds", FirestoreCodec.docId(id))))
        batch.deleteDocument(db.document(path("sessions", FirestoreCodec.docId(id))))
        write("delete session") { try await batch.commit() }
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
            write("clear history") { try await batch.commit() }
        }
    }

    func putHealth(_ row: HealthRow) {
        guard active, let data = try? FirestoreCodec.document(row) else { return }
        let ref = db.document(path("health", FirestoreCodec.docId(row.date)))
        write("health") { try await ref.setData(data) }
    }

    func putAISettings(_ settings: AISettings) {
        guard active, let data = try? FirestoreCodec.document(settings) else { return }
        let ref = db.document(path("state", "aiSettings"))
        write("aiSettings") { try await ref.setData(data) }
    }

    func logEvent(_ e: Event) {
        guard active, let data = try? FirestoreCodec.document(e) else { return }
        let ref = db.document(path("events", FirestoreCodec.eventDocId(e)))
        write("event") { try await ref.setData(data) }
    }

    /// Account state other than aiSettings; nil deletes the key.
    func stateValue(_ key: String) -> JSONValue? { state[key] }

    func setState(_ key: String, _ value: JSONValue?) {
        if offline || account == nil { state[key] = value; return }
        let ref = db.document(path("state", FirestoreCodec.docId(key)))
        state[key] = value
        onChange?("state")
        guard let value else { write("state \(key)") { try await ref.delete() }; return }
        let data: [String: Any] = [
            "value": FirestoreCodec.encode(value),
            "updatedAt": FirestoreCodec.encode(.number((Date().timeIntervalSince1970 * 1000).rounded())),
        ]
        write("state \(key)") { try await ref.setData(data) }
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
        write("github settings") { try await ref.updateData(["github": data]) }
    }

    /// Owner only — the rules reject anyone else.
    func setSharedGeminiKey(_ key: String) {
        shared["geminiKey"] = .string(key)
        onChange?("shared")
        guard active, account?.admin == true else { return }
        let ref = db.document("config/shared")
        write("shared key") { try await ref.setData(["geminiKey": key], merge: true) }
    }

    /// Awaited: the user is told it was sent.
    func sendFeedback(_ text: String) async throws {
        guard active, let account else { throw CloudError.signInFailed("Not signed in.") }
        try await db.collection(path("feedback")).document().setData([
            "text": text, "name": account.name, "email": account.email,
            "at": FirestoreCodec.encode(.number((Date().timeIntervalSince1970 * 1000).rounded())),
        ])
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
