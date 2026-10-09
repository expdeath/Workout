import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Sign in with Apple → Firebase (App Store guideline 4.8: an app that
/// offers Google sign-in must offer a privacy-friendly option too).
///
/// Off until the Apple Developer Program is set up: the capability needs a
/// paid team, so a free Personal Team build can't carry the entitlement.
/// docs/app-store.md has the switch-on steps (project.yml: the
/// `APPLE_SIGN_IN` compile flag + the applesignin entitlement; Firebase
/// console: enable the Apple provider). The code is always compiled.
enum AppleSignIn {
    static var enabled: Bool {
        #if APPLE_SIGN_IN
        true
        #else
        false
        #endif
    }

    struct Result {
        var idToken: String
        var rawNonce: String
        var fullName: PersonNameComponents?
        /// For revoking the Apple token when the account is deleted.
        var authorizationCode: String?
    }

    enum Failure: LocalizedError {
        case noToken
        var errorDescription: String? { "Apple didn't return an identity — try again." }
    }

    /// Random string sent hashed to Apple and raw to Firebase, so a
    /// replayed Apple token can't be used to sign in.
    static func randomNonce(_ length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func result(from auth: ASAuthorization, rawNonce: String) throws -> Result {
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8)
        else { throw Failure.noToken }
        return Result(
            idToken: token, rawNonce: rawNonce, fullName: cred.fullName,
            authorizationCode: cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    /// Runs the Apple sheet without a button (re-sign-in before deleting
    /// the account).
    @MainActor
    static func request() async throws -> Result {
        let nonce = randomNonce()
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.fullName, .email]
        req.nonce = sha256(nonce)
        let auth: ASAuthorization = try await withCheckedThrowingContinuation { cont in
            let delegate = Delegate(cont)
            let controller = ASAuthorizationController(authorizationRequests: [req])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            objc_setAssociatedObject(controller, &Delegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
        return try result(from: auth, rawNonce: nonce)
    }

    private final class Delegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        nonisolated(unsafe) static var key = 0
        private var cont: CheckedContinuation<ASAuthorization, Error>?
        init(_ c: CheckedContinuation<ASAuthorization, Error>) { cont = c }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            cont?.resume(returning: authorization)
            cont = nil
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            cont?.resume(throwing: error)
            cont = nil
        }
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
