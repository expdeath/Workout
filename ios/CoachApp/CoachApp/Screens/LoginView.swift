import SwiftUI

/// Sign-in gate — ports src/screens/Login.jsx. Any Google account gets
/// in: the first sign-in creates its account (Cloud.signUp), later ones
/// reopen it.
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

            Text("Any Google account works — new here? Your account is created on first sign-in.")
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
