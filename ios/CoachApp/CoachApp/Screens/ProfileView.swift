import SwiftUI

/// Edit profile — the name the app greets you by (state `displayName`,
/// shared with the web app) and your weekly session target. Google
/// still owns the sign-in email.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target = 3

    private var account: Cloud.AccountInfo? { Account.current() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Profile").font(Theme.head(26, weight: .bold)).textCase(.uppercase).tracking(0.6)
                Spacer()
                IconButton(icon: "xmark", label: "Close") { dismiss() }
            }

            HStack(spacing: 14) {
                Avatar(name: name.isEmpty ? appState.displayName : name, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? appState.displayName : name).font(Theme.body(18, weight: .bold)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusPill(text: account?.admin == true ? "Admin" : "Member", color: Theme.amberText, dot: false)
                        Text(account?.email ?? "").font(Theme.meta(12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 18)

            QLabel(text: "Display name")
            TextField("", text: $name, prompt: Text(account?.name ?? "Your name").foregroundStyle(Theme.dim))
                .textInputAutocapitalization(.words)
                .coachInput()

            QLabel(text: "Weekly target", value: "\(target) / week")
            Stepper("Sessions per week", value: $target, in: 1...14)
                .font(Theme.body(15)).foregroundStyle(Theme.textBody)
            Text("Sets your streak, consistency and the weekly target bar.")
                .font(Theme.body(13)).foregroundStyle(Theme.muted).padding(.top, 4)

            Spacer(minLength: 20)
            Button("Save") {
                appState.setDisplayName(name)
                LocalStore.shared.updateAISettings { $0.weeklyTarget = target }
                dismiss()
            }
            .buttonStyle(BigButtonStyle())
        }
        .padding(20)
        .coachScreen()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = appState.displayNameOverride ?? account?.name ?? ""
            target = Dashboard.weeklyTarget(LocalStore.shared.backup.aiSettings)
        }
    }
}
