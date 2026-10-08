import SwiftUI
import UniformTypeIdentifiers

/// Ports src/screens/Settings.jsx — account (feedback, sign out), AI
/// coach setup (+ the shared Gemini key, owner only), GitHub backup +
/// your data (export / CSV / import / clear), plates & bar, Apple Watch.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var open: Set<String> = []
    // coach setup
    @State private var key = Cloud.shared.geminiKey
    @State private var showKey = false
    @State private var ai = LocalStore.shared.backup.aiSettings
    @State private var saved = false
    // gym
    @State private var barKg = Helpers.fmtKg(LocalStore.shared.backup.aiSettings.barKg ?? Helpers.defaultBarKg)
    @State private var plates = LocalStore.shared.backup.aiSettings.plates ?? Helpers.defaultPlates.map(Helpers.fmtKg).joined(separator: ", ")
    @State private var gymSaved = false
    // backup
    @State private var repo = GitHubSync.config().repo
    @State private var token = GitHubSync.config().token
    @State private var showToken = false
    @State private var syncSaved = false
    @State private var syncMsg = ""
    @State private var syncing = false
    @State private var eventCount: Int?
    @State private var dataMsg = ""
    @State private var shareURL: URL?
    @State private var importing = false
    @State private var confirmClear = false
    // account
    @State private var feedback = ""
    @State private var feedbackMsg = ""
    @State private var sendingFb = false
    @State private var confirmOut = false
    // apple health
    @State private var healthBusy = false
    @State private var healthMsg = ""

    private var account: Cloud.AccountInfo? { Account.current() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenHeader(title: "Settings")
                if account != nil { accountSection }
                coachSection
                backupSection
                gymSection
                watchSection
                section("about", "About", status: nil) {
                    Text("COACH plans each session with Google Gemini from your check-in, history and recovery data. Your log lives in Firestore, backed up to your GitHub repo.")
                        .font(Theme.body(14)).foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
        .onAppear { if Cloud.shared.geminiKey.isEmpty { open.insert("coach") } }
        .task { eventCount = await Cloud.shared.countEvents() }
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        section("account", "Account", status: account?.email ?? account?.name ?? "") {
            QLabel(text: "Send feedback to Abhi")
            TextField("", text: Binding(get: { feedback }, set: { feedback = String($0.prefix(2000)) }),
                      prompt: Text("Bugs, ideas, anything…").foregroundStyle(Theme.dim), axis: .vertical)
                .lineLimit(3...8).coachInput()
            Button(sendingFb ? "Sending…" : "Send feedback") { Task { await sendFeedback() } }
                .buttonStyle(BigButtonStyle())
                .disabled(sendingFb || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !feedbackMsg.isEmpty { Text(feedbackMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amber) }
            Button(confirmOut ? "Tap again — this wipes this device" : "Sign out") {
                if confirmOut {
                    Task {
                        if let refusal = await appState.signOut() {
                            feedbackMsg = refusal
                            confirmOut = false
                        }
                    }
                } else { confirmOut = true }
            }
            .buttonStyle(BigButtonStyle(danger: true)).padding(.top, 8)
            Text("Signing out clears this device, including exercise photos. Your log stays in the cloud.")
                .font(Theme.body(13)).foregroundStyle(Theme.dim)
        }
    }

    private var coachSection: some View {
        let status = Cloud.shared.geminiKey.isEmpty
            ? (account?.admin == true ? "No API key yet — add one to start" : "No API key yet — ask Abhi to add one")
            : "Ready"
        return section("coach", "AI Coach", status: status) {
            if account?.admin == true {
                QLabel(text: "Gemini API key (shared)")
                HStack {
                    Group {
                        if showKey { TextField("", text: $key, prompt: Text("AIzaSy…").foregroundStyle(Theme.dim)) }
                        else { SecureField("", text: $key, prompt: Text("AIzaSy…").foregroundStyle(Theme.dim)) }
                    }
                    .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }.font(Theme.meta(13)).foregroundStyle(Theme.muted)
                }
                Text("Shared by everyone on COACH. Free at aistudio.google.com/apikey.")
                    .font(Theme.body(13)).foregroundStyle(Theme.muted)
            }
            QLabel(text: "About you")
            area($ai.profile, "e.g. Desk job, lower back gets tight", max: 1500)
            QLabel(text: "Goals (one per line)")
            area($ai.goals, "e.g.\nBench Press 80kg\n4 sessions a week", max: 600)
            QLabel(text: "Equipment")
            area($ai.equipment, "e.g. no cable tower, dumbbells to 40kg", max: 600)
            QLabel(text: "Base routine")
            area($ai.routine, "Empty = built-in Push/Pull/Legs", max: 4000, minLines: 3)
            Button(saved ? "✓ Saved" : "Save coach setup") {
                if account?.admin == true, key.trimmingCharacters(in: .whitespaces) != Cloud.shared.geminiKey {
                    Cloud.shared.setSharedGeminiKey(key.trimmingCharacters(in: .whitespaces))
                    LocalStore.shared.logEvent(type: "api_key_saved")
                }
                LocalStore.shared.updateAISettings { s in
                    s.profile = ai.profile.trimmingCharacters(in: .whitespacesAndNewlines)
                    s.goals = ai.goals.trimmingCharacters(in: .whitespacesAndNewlines)
                    s.equipment = ai.equipment.trimmingCharacters(in: .whitespacesAndNewlines)
                    s.routine = ai.routine.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                LocalStore.shared.logEvent(type: "ai_settings_saved")
                flash($saved)
            }
            .buttonStyle(BigButtonStyle()).padding(.top, 10)
        }
    }

    private var backupSection: some View {
        let last = GitHubSync.lastSync()
        let status: String = {
            if last?.status == "ok", let at = ISO8601DateFormatter.withMillis.date(from: last!.at) ?? ISO8601DateFormatter().date(from: last!.at) {
                return "Backed up \(at.formatted(date: .abbreviated, time: .shortened))"
            }
            if last?.status == "error" { return "Backup failed: \(last?.message ?? "")" }
            return repo.isEmpty || token.isEmpty ? "Synced · no GitHub backup" : "Synced · backup pending"
        }()
        return section("sync", "Sync & Backup", status: status) {
            QLabel(text: "GitHub backup")
            TextField("", text: $repo, prompt: Text("your-username/workout-data").foregroundStyle(Theme.dim))
                .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
            HStack {
                Group {
                    if showToken { TextField("", text: $token, prompt: Text("github_pat_…").foregroundStyle(Theme.dim)) }
                    else { SecureField("", text: $token, prompt: Text("github_pat_…").foregroundStyle(Theme.dim)) }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
                Button(showToken ? "Hide" : "Show") { showToken.toggle() }.font(Theme.meta(13)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                Button(syncSaved ? "✓ Saved" : "Save settings") {
                    GitHubSync.setConfig(token: token, repo: repo)
                    LocalStore.shared.logEvent(type: "sync_config_saved", data: ["repo": .string(repo)])
                    flash($syncSaved)
                }
                .buttonStyle(BigButtonStyle())
                Button(syncing ? "Backing up…" : "Back up now") { Task { await backUpNow() } }
                    .buttonStyle(BigButtonStyle()).disabled(syncing)
            }
            if !syncMsg.isEmpty { Text(syncMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amber) }
            Text("Fine-grained token, your data repo only, Contents: read & write.")
                .font(Theme.body(13)).foregroundStyle(Theme.muted)

            QLabel(text: "Your data")
            Text("\(appState.history.count) sessions · \(eventCount.map(String.init) ?? "…") events")
                .font(Theme.meta(13)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Chip(title: "Export") { Task { do { shareURL = try await appState.exportBackupFile() } catch { dataMsg = "Export failed: \(error.localizedDescription)" } } }
                Chip(title: "Import") { importing = true }
                Chip(title: "Export CSV") { do { shareURL = try appState.exportCsvFile() } catch { dataMsg = "Export failed: \(error.localizedDescription)" } }
            }
            if !dataMsg.isEmpty { Text(dataMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amber) }
            Button(confirmClear ? "Tap again to confirm" : "Clear all history") {
                if confirmClear { confirmClear = false; Task { await appState.clearHistory() } } else { confirmClear = true }
            }
            .buttonStyle(BigButtonStyle(danger: true)).padding(.top, 6)
        }
    }

    private var gymSection: some View {
        let shownPlates = (Helpers.parsePlates(plates) ?? Helpers.defaultPlates).map(Helpers.fmtKg).joined(separator: "/")
        return section("gym", "Plates & Bar", status: "\(Helpers.fmtKg(Double(barKg) ?? Helpers.defaultBarKg))kg bar · \(shownPlates)") {
            QLabel(text: "Bar weight (kg)")
            TextField("", text: Binding(get: { barKg }, set: { barKg = $0.filter { $0.isNumber || $0 == "." } }))
                .keyboardType(.decimalPad).coachInput()
            QLabel(text: "Plates (kg, per pair)")
            TextField("", text: $plates, prompt: Text(Helpers.defaultPlates.map(Helpers.fmtKg).joined(separator: ", ")).foregroundStyle(Theme.dim))
                .coachInput()
            Button(gymSaved ? "✓ Saved" : "Save gym setup") {
                LocalStore.shared.updateAISettings { s in
                    s.barKg = min(max(Double(barKg) ?? Helpers.defaultBarKg, 0), 40)
                    s.plates = plates.trimmingCharacters(in: .whitespaces)
                }
                LocalStore.shared.logEvent(type: "gym_settings_saved")
                flash($gymSaved)
            }
            .buttonStyle(BigButtonStyle()).padding(.top, 10)
        }
    }

    private var watchSection: some View {
        let today = Cloud.shared.stateValue("healthText-\(Helpers.todayStr())")
        let text: String? = { if case .string(let t)? = today { return t }; return nil }()
        return section("watch", "Apple Health", status: text == nil ? (HealthKitSync.requested ? "Connected · nothing today yet" : "Not connected") : "Received today",
                       statusColor: text == nil ? nil : Theme.teal) {
            if let text {
                Text("Today: \(Stats.fmtHealthLine(Stats.parseHealthNumbers(text)).isEmpty ? text : Stats.fmtHealthLine(Stats.parseHealthNumbers(text)))")
                    .font(Theme.body(14)).foregroundStyle(Theme.teal)
            }
            if !HealthKitSync.isAvailable {
                Text("Apple Health isn't available on this device.").font(Theme.body(13)).foregroundStyle(Theme.muted)
            } else {
                Text(HealthKitSync.requested
                     ? "Reads HRV, resting HR, sleep and more each time the app opens. Change access in iPhone Settings → Health."
                     : "Read-only. COACH never writes to Health.")
                    .font(Theme.body(13)).foregroundStyle(Theme.muted)
                Button(healthBusy ? "Reading Apple Health…" : (HealthKitSync.requested ? "Read Apple Health now" : "Connect Apple Health")) {
                    Task { await connectHealth() }
                }
                .buttonStyle(BigButtonStyle())
                .disabled(healthBusy)
                if !healthMsg.isEmpty { Text(healthMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amber) }
            }
        }
    }

    private func connectHealth() async {
        healthBusy = true
        healthMsg = ""
        do {
            try await HealthKitSync.shared.requestAccess()
            let n = await HealthKitSync.shared.sync()
            healthMsg = n > 0 ? "✓ Read \(n) day\(n == 1 ? "" : "s") from Apple Health." : "Nothing new in Apple Health — if that's unexpected, check iPhone Settings → Health → Data Access & Devices → COACH."
        } catch {
            healthMsg = "Couldn't open Apple Health: \(error.localizedDescription)"
        }
        healthBusy = false
    }

    // MARK: - Actions

    private func sendFeedback() async {
        sendingFb = true
        feedbackMsg = ""
        do {
            try await GitHubSync.sendFeedback(feedback)
            LocalStore.shared.logEvent(type: "feedback_sent", data: ["chars": .number(Double(feedback.count))])
            feedback = ""
            feedbackMsg = "✓ Sent — thank you!"
        } catch {
            feedbackMsg = error.localizedDescription
        }
        sendingFb = false
    }

    private func backUpNow() async {
        syncing = true
        syncMsg = "Backing up…"
        do {
            let r = try await GitHubSync.syncNow(force: true)
            syncMsg = r.status == .unconfigured ? "Add your token and repo first, then Save." : "✓ Backed up — \(r.sessions) sessions on GitHub"
        } catch {
            syncMsg = "Backup failed: \(error.localizedDescription)"
        }
        syncing = false
    }

    private func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            dataMsg = try await appState.importBackup(try Data(contentsOf: url))
        } catch {
            dataMsg = "Import failed: \(error.localizedDescription)"
        }
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flag.wrappedValue = false }
    }

    // MARK: - Pieces

    /// `.section` — collapsible card with a status line.
    private func section(_ id: String, _ title: String, status: String?, statusColor: Color? = nil, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { if open.contains(id) { open.remove(id) } else { open.insert(id) } }
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Theme.body(16, weight: .semibold)).foregroundStyle(Theme.text)
                        if let status, !status.isEmpty { Text(status).font(Theme.meta(13)).foregroundStyle(statusColor ?? Theme.muted).multilineTextAlignment(.leading).lineLimit(1) }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).rotationEffect(.degrees(open.contains(id) ? 180 : 0)).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open.contains(id) { content() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func area(_ text: Binding<String>, _ placeholder: String, max: Int, minLines: Int = 3) -> some View {
        TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(max)) }),
                  prompt: Text(placeholder).foregroundStyle(Theme.dim), axis: .vertical)
            .lineLimit(minLines...12)
            .coachInput()
    }
}

private struct ShareItem: Identifiable { let url: URL; var id: URL { url } }

/// The iOS share sheet for an exported file (save to Files, AirDrop…).
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
