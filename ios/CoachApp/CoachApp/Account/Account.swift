import Foundation

/// Accounts: Google sign-in + an owner-managed allowlist (port of
/// src/utils/account.js). There's no signup — the owner adds a person's
/// Google email to allowlist/{email} in Firestore; signing in with that
/// Google account opens their account on any device, web or iOS.
/// Revoking = deleting the allowlist entry.
enum Account {
    /// The signed-in account, or nil.
    static func current() -> Cloud.AccountInfo? { Cloud.shared.account }

    /// Boot: the Google/Firebase user restored from the keychain → their
    /// account. nil when nobody is signed in; throws CloudError.notInvited
    /// for an email that isn't on the allowlist.
    static func resume() async throws -> Cloud.AccountInfo? {
        guard let user = Cloud.shared.signedInUser else { return nil }
        return try await Cloud.shared.start(user: user)
    }

    /// The Login screen's button.
    @MainActor
    static func signIn() async throws -> Cloud.AccountInfo {
        let user = try await Cloud.shared.signInWithGoogle()
        do {
            return try await Cloud.shared.start(user: user)
        } catch {
            await Cloud.shared.signOut() // not invited → don't stay half signed in
            throw error
        }
    }

    /// Clears everything this device kept for the old invite-code setup
    /// (Keychain secrets, settings) and the in-memory mirror.
    static func wipeLocal() {
        Keychain.removeAll()
        Defaults.removeAll()
        LocalStore.shared.wipe()
    }

    /// Sign out: this device forgets the account (data stays in the cloud).
    static func signOut() async {
        await Cloud.shared.signOut()
        wipeLocal()
    }
}
