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
        // the coach is one tap away from every tab (the workout and
        // session detail have their own chat entry; check-in and finish
        // stay focused)
        .overlay(alignment: .bottomTrailing) {
            if !appState.chatOpen, isTab {
                Button { appState.chatOpen = true } label: {
                    Image(systemName: "bubble.left.fill").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 52, height: 52)
                        .background(Theme.amber)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                }
                .accessibilityLabel("Ask the coach")
                .padding(.trailing, 16).padding(.bottom, 12)
            }
        }
        // room under the last card so the coach button never covers it
        .contentMargins(.bottom, isTab ? 72 : 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isTab { TabBar() }
        }
        .sheet(isPresented: Binding(get: { appState.chatOpen }, set: { appState.chatOpen = $0 })) {
            CoachChatView().environment(appState)
        }
    }

    private var isTab: Bool { TabBar.tabs.contains { $0.screen == appState.screen } }
}

/// The bottom tab bar on the five top-level screens.
struct TabBar: View {
    @Environment(AppState.self) private var appState

    static let tabs: [(screen: Screen, icon: String, label: String)] = [
        (.home, "house", "Today"),
        (.history, "list.bullet", "Log"),
        (.progress, "chart.line.uptrend.xyaxis", "Progress"),
        (.records, "trophy", "Records"),
        (.settings, "gearshape", "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs, id: \.label) { tab in
                let on = appState.screen == tab.screen
                Button { appState.screen = tab.screen } label: {
                    VStack(spacing: 3) {
                        Image(systemName: on ? tab.icon + (tab.icon == "list.bullet" || tab.icon.hasPrefix("chart") ? "" : ".fill") : tab.icon)
                            .font(.system(size: 19, weight: on ? .semibold : .regular))
                            .frame(height: 24)
                        Text(tab.label).font(Theme.body(10.5, weight: .medium))
                    }
                    .foregroundStyle(on ? Theme.amber : Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8).padding(.bottom, 4)
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
