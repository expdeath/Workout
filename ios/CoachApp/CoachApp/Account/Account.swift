import Foundation

/// Accounts: Google sign-in + the Firestore allowlist (port of
/// src/utils/account.js). Anyone can sign in: a Google account's first
/// sign-in creates its own allowlist entry and empty account (selfServe;
/// it brings its own Gemini key). Entries the owner adds are "invited"
/// and share the owner's key. The same Google account opens the same
/// account on any device, web or iOS; blocked: true turns one off.
enum Account {
    /// The signed-in account, or nil.
    static func current() -> Cloud.AccountInfo? { Cloud.shared.account }

    /// Boot: the Google/Firebase user restored from the keychain → their
    /// account. nil when nobody is signed in; throws CloudError.blocked
    /// for an account the owner turned off.
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
            await Cloud.shared.signOut() // blocked / couldn't open → don't stay half signed in
            throw error
        }
    }

    /// Clears everything this device kept for the old invite-code setup
    /// (Keychain secrets, settings) and the in-memory mirror.
    static func wipeLocal() {
        Keychain.removeAll()
        Defaults.removeAll()
        LocalStore.shared.wipe()
        MediaStore.removeAll() // form photos/clips live only on this device
    }

    /// Sign out: this device forgets the account (data stays in the cloud).
    static func signOut() async {
        await Cloud.shared.signOut()
        wipeLocal()
    }
}
