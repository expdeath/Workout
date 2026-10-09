import SwiftUI

/// Asked once per account, before anything is sent to Google Gemini —
/// App Store guideline 5.1.2(i). Ports src/screens/AIConsent.jsx; the
/// answer is account state `aiConsent`, shared with the web app, and
/// Settings → AI Coach changes it.
struct AIConsentView: View {
    @Environment(AppState.self) private var appState

    /// What goes to Gemini — also listed under Settings → AI Coach.
    static let shared: [(icon: String, title: String, sub: String)] = [
        ("dumbbell", "Your workouts", "Logged sessions, sets and weights, goals, equipment, profile notes"),
        ("square.and.pencil", "Your check-ins and chats", "Energy, sleep, soreness, body weight, notes, questions you ask the coach"),
        ("heart.text.square", "Apple Health / Watch data", "HRV, resting heart rate, sleep, steps, active energy"),
        ("photo", "Photos you choose", "Only a program photo you add in “Build with coach” — read, never stored by COACH"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                IconWell(icon: "brain.head.profile", size: 56).padding(.top, 28)
                Text("Your AI coach").font(Theme.head(34, weight: .bold)).textCase(.uppercase)
                (Text("COACH plans your sessions with ") + Text("Google Gemini").bold() + Text(", an AI service run by Google. To do that it sends Gemini:"))
                    .font(Theme.body(15)).foregroundStyle(Theme.textBody)
                ForEach(Self.shared, id: \.title) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon).foregroundStyle(Theme.amberText).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(Theme.body(15, weight: .semibold))
                            Text(item.sub).font(Theme.meta(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                Text(.init("With your own Gemini key it goes straight from your phone to Google, under [Google's Gemini API terms](https://ai.google.dev/gemini-api/terms) — on free keys Google may use it to improve its products. With COACH Pro it goes through COACH's server, which passes it on without keeping it, to COACH's paid Gemini account — which Google doesn't use to improve its products. Nothing is sent until you allow it, and you can turn it off any time in Settings → AI Coach. [Privacy policy](https://expdeath.github.io/Workout/privacy.html)"))
                    .font(Theme.meta(12.5)).foregroundStyle(Theme.muted).tint(Theme.amberText)
                Button("Allow the AI coach") { appState.aiConsentAnswered(true) }
                    .buttonStyle(BigButtonStyle())
                    .accessibilityIdentifier("allowAI")
                Button("Not now") { appState.aiConsentAnswered(false) }
                    .font(Theme.body(15, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                Text("Without it you can still log workouts and run your saved workouts as written.")
                    .font(Theme.meta(12.5)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
        }
        .coachScreen()
    }
}
