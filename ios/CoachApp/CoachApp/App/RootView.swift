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
            case .workout:
                WorkoutView()
            case .finish:
                FinishView()
            case .history:
                HistoryView()
            case .historyDetail:
                HistoryDetailView()
            case .addPast:
                AddPastView()
            case .settings:
                SettingsView()
            case .records:
                RecordsView()
            case .progress:
                ProgressScreen()
            }
        }
        .preferredColorScheme(.dark) // the web app is dark-only; match it
        // the coach is one tap away from anywhere (hidden on workout,
        // generating and history detail, which have their own chat entry)
        .overlay(alignment: .bottomTrailing) {
            if !appState.chatOpen, Self.chatFabScreens.contains(appState.screen) {
                Button { appState.chatOpen = true } label: {
                    Text("🗨").font(.system(size: 24))
                        .frame(width: 56, height: 56)
                        .background(Theme.amber)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                }
                .accessibilityLabel("Ask the coach")
                .padding(.trailing, 18).padding(.bottom, 18)
            }
        }
        .sheet(isPresented: Binding(get: { appState.chatOpen }, set: { appState.chatOpen = $0 })) {
            CoachChatView().environment(appState)
        }
    }

    private static let chatFabScreens: Set<Screen> = [.home, .checkIn, .finish, .progress, .history, .records, .settings]
}
