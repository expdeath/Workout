import SwiftUI

/// The bell's inbox — reviews, new records, milestones and deload
/// warnings (Dashboard.notifications), newest first. Opening it marks
/// everything read; tapping one jumps to where it lives.
struct NotificationsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var seenBefore: Double = 0

    var body: some View {
        let items = appState.notifications
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications").font(Theme.head(26, weight: .bold)).textCase(.uppercase).tracking(0.6)
                Spacer()
                IconButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 16).padding(.top, 14)

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash").font(.system(size: 28)).foregroundStyle(Theme.dim)
                    Text("Nothing yet — reviews, records and milestones show up here.")
                        .font(Theme.body(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(items) { n in row(n, unread: n.at > seenBefore) }
                    }
                    .padding(16)
                }
            }
        }
        .coachScreen()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            seenBefore = appState.notifSeenAt
            appState.markNotificationsSeen()
        }
    }

    private func row(_ n: Dashboard.Notice, unread: Bool) -> some View {
        Button {
            dismiss()
            appState.screen = n.screen
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconWell(icon: n.icon, tint: n.icon.hasPrefix("exclamation") ? Theme.red : Theme.amberText, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.title).font(Theme.body(15, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Self.ago(n.at)).font(Theme.meta(12)).foregroundStyle(Theme.dim)
                    }
                    Text(n.body).font(Theme.body(13.5)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                if unread { Circle().fill(Theme.amber).frame(width: 7, height: 7).padding(.top, 6) }
            }
            .padding(12)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }

    /// "2h", "3d", "Sep 12"
    static func ago(_ ms: Double) -> String {
        let s = Date().timeIntervalSince1970 - ms / 1000
        if s < 3600 { return "\(max(Int(s / 60), 1))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86400 { return "\(Int(s / 86400))d" }
        return Date(timeIntervalSince1970: ms / 1000).formatted(.dateTime.month(.abbreviated).day())
    }
}
