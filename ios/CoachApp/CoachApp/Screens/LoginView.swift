import SwiftUI

/// First-run gate for invited users — ports src/screens/Login.jsx.
/// There's deliberately no signup: the only way in is an invite code
/// provisioned by the owner (docs/accounts.md).
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("COACH")
                .font(Theme.head(40, weight: .bold))
                .textCase(.uppercase)
                .tracking(14)
                .foregroundStyle(Theme.amber)
                .padding(.leading, 14) // balances the trailing tracking so the wordmark reads centered

            Text("Your AI training coach. This is a private beta — you'll need the invite code you were sent.")
                .font(Theme.body(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $code)
                    .font(Theme.mono(14.5))
                    .frame(height: 90)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.text)
                    .padding(8)
                if code.isEmpty {
                    Text("Paste your invite code…")
                        .font(Theme.mono(14.5))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.bgInput)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.borderDim))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .padding(.horizontal, 24)

            if let error {
                Text(error)
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 24)
            }

            Button(busy ? "Setting up…" : "Let's train") {
                redeem()
            }
            .buttonStyle(BigButtonStyle())
            .disabled(busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            .padding(.horizontal, 24)

            Text("No code? Ask Abhi for one — accounts are invite-only for now.")
                .font(Theme.mono(12.5))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .coachScreen()
    }

    private func redeem() {
        error = nil
        let acct: InviteCode
        do {
            acct = try Account.parseInviteCode(code)
        } catch {
            self.error = error.localizedDescription
            return
        }
        busy = true
        // stale local data must not ride into this account
        Account.wipeLocal()
        Account.apply(acct)
        LocalStore.shared.logEvent(type: "invite_redeemed", data: [
            "name": .string(acct.name),
            "repo": .string(acct.repo),
        ])
        busy = false
        appState.screen = .home
    }
}

#Preview {
    LoginView().environment(AppState())
}
