import SwiftUI

/// Sign-in gate — ports src/screens/Login.jsx. There's deliberately no
/// signup: Google proves who you are, and only emails the owner has
/// added to the allowlist get in.
struct LoginView: View {
    @Environment(AppState.self) private var appState
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

            Text("Your AI training coach.")
                .font(Theme.body(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)

            if !appState.loginError.isEmpty {
                Text(appState.loginError)
                    .font(Theme.body(13.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 24)
            }

            Button(busy ? "Signing in…" : "Sign in with Google") {
                Task {
                    busy = true
                    await appState.signIn()
                    busy = false
                }
            }
            .buttonStyle(BigButtonStyle())
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
            .padding(.horizontal, 24)

            Text("Private beta — ask Abhi for an invite.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .coachScreen()
    }
}

#Preview {
    LoginView().environment(AppState())
}
