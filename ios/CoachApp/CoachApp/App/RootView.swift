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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isTab { TabBar() }
        }
        .sheet(isPresented: Binding(get: { appState.chatOpen }, set: { appState.chatOpen = $0 })) {
            CoachChatView().environment(appState)
        }
        .sheet(item: Binding(get: { appState.sheet }, set: { appState.sheet = $0 })) { sheet in
            switch sheet {
            case .notifications: NotificationsView().environment(appState)
            case .profile: ProfileView().environment(appState)
            }
        }
    }

    private var isTab: Bool { TabBar.tabs.contains { $0.screen == appState.screen } }
}

/// The bottom tab bar on the five top-level screens.
struct TabBar: View {
    @Environment(AppState.self) private var appState

    static let tabs: [(screen: Screen, icon: String, label: String)] = [
        (.home, "bolt", "Today"),
        (.history, "calendar", "Log"),
        (.progress, "chart.bar.xaxis", "Progress"),
        (.records, "trophy", "Records"),
        (.settings, "slider.horizontal.3", "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs, id: \.label) { tab in
                let on = appState.screen == tab.screen
                Button { appState.screen = tab.screen } label: {
                    VStack(spacing: 4) {
                        Image(systemName: on && ["bolt", "trophy"].contains(tab.icon) ? tab.icon + ".fill" : tab.icon)
                            .font(.system(size: 18, weight: on ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tab.label).capsLabel(on ? Theme.amberText : Theme.dim, size: 11)
                    }
                    .foregroundStyle(on ? Theme.amberText : Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9).padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(Theme.bgCard.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
