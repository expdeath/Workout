import SwiftUI

/// Ports src/screens/Generating.jsx — shown while Gemini builds the
/// plan. Cycles reassurance lines unless the model-fallback ladder has a
/// live status to show (AppState.statusMsg).
struct GeneratingView: View {
    @Environment(AppState.self) private var appState
    @State private var msg = 0
    @State private var pulse = false

    private static let messages = [
        "Reading your training log…",
        "Checking recovery signals…",
        "Weighing volume vs. your evening…",
        "Building the session…",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("COACH")
                .font(Theme.head(40, weight: .bold))
                .textCase(.uppercase)
                .tracking(14)
                .padding(.leading, 14) // balances trailing tracking
                .foregroundStyle(Theme.amber)
                .opacity(pulse ? 0.45 : 1)

            ReadinessBar(value: Helpers.quickReadiness(appState.ci), label: "Readiness (initial estimate)")
                .frame(maxWidth: 320)
                .padding(.top, 28)

            Text(appState.statusMsg.isEmpty ? Self.messages[msg] : appState.statusMsg)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .coachScreen()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                msg = (msg + 1) % Self.messages.count
            }
        }
    }
}

#Preview {
    GeneratingView().environment(AppState())
}
