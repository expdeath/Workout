import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.screen {
            case .loading:
                ProgressView()
                    .tint(Theme.amber)
                    .coachScreen()
            case .login:
                LoginView()
            case .home:
                HomeView()
            case .checkIn:
                CheckInView()
            case .generating:
                GeneratingView()
            default:
                ComingSoonView(screen: appState.screen)
            }
        }
        .preferredColorScheme(.dark) // the web app is dark-only; match it
    }
}

/// Placeholder for screens not yet ported. Removed as each phase lands.
private struct ComingSoonView: View {
    let screen: Screen

    var body: some View {
        VStack(spacing: 8) {
            Text("COACH")
                .font(Theme.head(22, weight: .bold))
                .textCase(.uppercase)
                .tracking(5)
                .foregroundStyle(Theme.amber)
            Text("\(String(describing: screen)) — coming soon")
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
        }
        .coachScreen()
    }
}
