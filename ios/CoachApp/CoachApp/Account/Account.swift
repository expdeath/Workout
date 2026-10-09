import Foundation

/// Invite-code based accounts — ports src/utils/account.js. There's no
/// signup: the owner provisions each account by hand (a private GitHub
/// data repo + a fine-grained PAT scoped to it, optionally a Gemini key)
/// and hands it out as one base64url invite code from
/// scripts/make-invite.js. Redeeming a code just fills the same
/// Keychain/Defaults slots the rest of the app already reads — sync and
/// the AI need no changes. Uses the identical encoding as the web app so
/// existing invite codes work unmodified.
struct InviteCode: Codable {
    var name: String
    var repo: String
    var ghToken: String
    var geminiKey: String?
}

struct StoredAccount: Codable {
    var name: String
    var since: String
}

enum AccountError: LocalizedError {
    case empty
    case malformed
    case incomplete

    var errorDescription: String? {
        switch self {
        case .empty: return "Paste the invite code you were sent."
        case .malformed: return "That doesn't look like a COACH invite code — check you copied all of it."
        case .incomplete: return "Invite code is incomplete — ask for a new one."
        }
    }
}

enum Account {
    private static let accountKey = "account"

    static func current() -> StoredAccount? {
        Defaults.codable(StoredAccount.self, accountKey)
    }

    /// True on a fresh install with no account and no hand-entered setup
    /// (pre-account installs keep working without ever seeing Login).
    static func needsLogin() -> Bool {
        current() == nil && Keychain.apiKey.isEmpty && GitHubSync.config().token.isEmpty
    }

    /// Decode + validate an invite code. Accepts either the bare code or
    /// a full magic link (https://…/#invite=<code>) — the web app only
    /// auto-extracts the code from a link via App.jsx's boot-time hash
    /// parsing (a separate path from the Login screen's paste box, which
    /// expects the bare code same as here); since this app has no
    /// equivalent hash-based entry point, pasting the whole link into
    /// this box needs to work directly instead. Throws a user-readable
    /// error.
    static func parseInviteCode(_ code: String) throws -> InviteCode {
        var raw = code.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard !raw.isEmpty else { throw AccountError.empty }
        if let g = Stats.firstMatch(#"[#&]invite=([A-Za-z0-9_-]+)"#, in: raw), g.count > 1, let extracted = g[1] {
            raw = extracted
        }

        var b64 = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - b64.count % 4) % 4
        b64 += String(repeating: "=", count: padding)

        guard let data = Data(base64Encoded: b64) else { throw AccountError.malformed }
        guard let acct = try? JSONDecoder().decode(InviteCode.self, from: data) else {
            throw AccountError.malformed
        }
        guard !acct.name.isEmpty, !acct.repo.isEmpty, !acct.ghToken.isEmpty else {
            throw AccountError.incomplete
        }
        return acct
    }

    /// Redeem: write the config the rest of the app already reads.
    static func apply(_ acct: InviteCode) {
        GitHubSync.setConfig(token: acct.ghToken, repo: acct.repo)
        if let key = acct.geminiKey, !key.isEmpty {
            Keychain.apiKey = key
        }
        let stored = StoredAccount(name: acct.name, since: ISO8601DateFormatter().string(from: Date()))
        Defaults.setCodable(stored, for: accountKey)
    }

    /// Clears every stored secret/setting and the local backup file
    /// (cloud copies untouched).
    static func wipeLocal() {
        Keychain.removeAll()
        Defaults.removeAll()
        LocalStore.shared.wipe()
    }

    /// Wipes this device back to the login screen (data stays in the cloud).
    static func signOut() {
        wipeLocal()
    }
}
