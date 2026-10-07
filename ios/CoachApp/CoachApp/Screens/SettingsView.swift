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

    private var account: Cloud.AccountInfo? { Account.current() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenHeader(back: "Home", title: "SETTINGS", onBack: { appState.screen = .home })
                if account != nil { accountSection }
                coachSection
                backupSection
                gymSection
                watchSection
                section("about", "About", status: nil) {
                    Text("COACH is a personal workout planner powered by Google Gemini AI. It builds daily sessions from your check-in, training history, and recovery data. Your log is stored in Google Cloud Firestore under your Google sign-in, with a backup copy in your private GitHub repo.")
                        .font(Theme.body(14)).foregroundStyle(Theme.muted)
                }
                Spacer().frame(height: 24)
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
        section("account", "Account", status: "Signed in as \(account?.name.isEmpty == false ? account!.name : account?.email ?? "")", statusColor: Theme.teal) {
            Text("Hey \(account?.name ?? "") — you're on the COACH private beta. Found a bug, or something felt off mid-workout? Tell Abhi here:")
                .font(Theme.body(14)).foregroundStyle(Theme.muted)
            TextField("", text: Binding(get: { feedback }, set: { feedback = String($0.prefix(2000)) }),
                      prompt: Text("What worked, what didn't, what you'd change…").foregroundStyle(Theme.dim), axis: .vertical)
                .lineLimit(3...8).coachInput()
            Button(sendingFb ? "Sending…" : "Send feedback") { Task { await sendFeedback() } }
                .buttonStyle(BigButtonStyle())
                .disabled(sendingFb || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !feedbackMsg.isEmpty { Text(feedbackMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amber) }
            Button(confirmOut ? "Tap again — this wipes this device" : "Sign out") {
                if confirmOut { Task { await appState.signOut() } } else { confirmOut = true }
            }
            .buttonStyle(BigButtonStyle(danger: true)).padding(.top, 8)
            Text("Signed in with Google as \(account?.email ?? ""). Signing out clears this device (exercise photos/clips included — they only live here). Your training log is safe in the cloud and comes back when you sign in again.")
                .font(Theme.body(12.5)).foregroundStyle(Theme.dim)
        }
    }

    private var coachSection: some View {
        let status = Cloud.shared.geminiKey.isEmpty
            ? (account?.admin == true ? "No API key yet — add one to start" : "No API key yet — ask Abhi to add one")
            : "Shared API key set\(LocalStore.shared.backup.aiSettings.profile.isEmpty ? "" : " · custom profile set")"
        return section("coach", "AI Coach", status: status) {
            if account?.admin == true {
                QLabel(text: "Gemini API key (shared)")
                HStack {
                    Group {
                        if showKey { TextField("", text: $key, prompt: Text("AIzaSy…").foregroundStyle(Theme.dim)) }
                        else { SecureField("", text: $key, prompt: Text("AIzaSy…").foregroundStyle(Theme.dim)) }
                    }
                    .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }.font(Theme.mono(13)).foregroundStyle(Theme.muted)
                }
                Text("One key for everyone on COACH — saved in the cloud, readable only by invited accounts, and only ever sent to Google's Gemini API. Get one free at aistudio.google.com/apikey.")
                    .font(Theme.body(12.5)).foregroundStyle(Theme.muted)
            } else {
                Text(Cloud.shared.geminiKey.isEmpty ? "The AI coach needs a key — Abhi hasn't added the shared one yet." : "The AI coach runs on the shared key Abhi set up — nothing to configure.")
                    .font(Theme.body(13)).foregroundStyle(Theme.muted)
            }
            QLabel(text: "About you")
            area($ai.profile, "e.g. Desk job, long sitting. Goals: fat loss + muscle. Lower back gets tight — prefer supported variations.", max: 1500)
            QLabel(text: "Goals (one per line)")
            area($ai.goals, "e.g.\nBench Press 80kg\n4 sessions a week", max: 600)
            Text("The coach plans toward these; lift and frequency goals get progress bars in Stats.")
                .font(Theme.body(12.5)).foregroundStyle(Theme.muted)
            QLabel(text: "Gym equipment & limits")
            area($ai.equipment, "What your gym has (or lacks) — e.g. no cable tower · dumbbells up to 40kg", max: 600)
            QLabel(text: "Your base routine")
            area($ai.routine, "Leave empty to use the built-in Push/Pull/Legs routine, or paste your own.", max: 4000, minLines: 5)
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
                return "☁ live in the cloud · GitHub backup \(at.formatted(date: .abbreviated, time: .shortened))"
            }
            if last?.status == "error" { return "☁ live in the cloud · GitHub backup failed: \(last?.message ?? "")" }
            return repo.isEmpty || token.isEmpty ? "☁ live in the cloud · add a GitHub token for backups" : "☁ live in the cloud · GitHub backup not run yet"
        }()
        return section("sync", "Sync & Backup", status: status) {
            Text("Your training log lives in the cloud and syncs live to every device you sign in on. A full backup copy also goes to your private GitHub repo whenever it changes — at most every 10 minutes, and at least daily.")
                .font(Theme.body(14)).foregroundStyle(Theme.muted)
            TextField("", text: $repo, prompt: Text("your-username/workout-data").foregroundStyle(Theme.dim))
                .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
            HStack {
                Group {
                    if showToken { TextField("", text: $token, prompt: Text("github_pat_…").foregroundStyle(Theme.dim)) }
                    else { SecureField("", text: $token, prompt: Text("github_pat_…").foregroundStyle(Theme.dim)) }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
                Button(showToken ? "Hide" : "Show") { showToken.toggle() }.font(Theme.mono(13)).foregroundStyle(Theme.muted)
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
            Text("Token setup (once): github.com → Settings → Developer settings → Fine-grained tokens → Generate. Repository access: only your data repo. Permissions: Contents → Read and write. It's saved to your account (so all your devices can back up) and only ever sent to api.github.com.")
                .font(Theme.body(12.5)).foregroundStyle(Theme.muted)

            QLabel(text: "Your data")
            Text("\(appState.history.count) sessions · \(eventCount.map(String.init) ?? "…") events logged")
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Chip(title: "Export backup") { Task { do { shareURL = try await appState.exportBackupFile() } catch { dataMsg = "Export failed: \(error.localizedDescription)" } } }
                Chip(title: "Import backup") { importing = true }
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
        return section("gym", "Plates & Bar", status: "\(Helpers.fmtKg(Double(barKg) ?? Helpers.defaultBarKg))kg bar · plates \(shownPlates)") {
            Text("Powers the ⚖ plates button during a workout — tap it on any exercise to see exactly what to load per side.")
                .font(Theme.body(14)).foregroundStyle(Theme.muted)
            QLabel(text: "Bar weight (kg)")
            TextField("", text: Binding(get: { barKg }, set: { barKg = $0.filter { $0.isNumber || $0 == "." } }))
                .keyboardType(.decimalPad).coachInput()
            QLabel(text: "Available plates (kg, per pair)")
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
        return section("watch", "⌚ Apple Watch", status: text == nil ? "Nothing received today yet" : "Received today",
                       statusColor: text == nil ? nil : Theme.teal) {
            if let text {
                Text("⌚ Today: \(Stats.fmtHealthLine(Stats.parseHealthNumbers(text)).isEmpty ? text : Stats.fmtHealthLine(Stats.parseHealthNumbers(text)))")
                    .font(Theme.body(14)).foregroundStyle(Theme.teal)
            } else {
                Text("⌚ Nothing received today yet — run the Gym Check-in shortcut.").font(Theme.body(14)).foregroundStyle(Theme.muted)
            }
            if let inbox = GitHubSync.lastInbox() {
                Text("📥 Last delivery on this device: \(inbox.files) file\(inbox.files > 1 ? "s" : ""), \(Date(timeIntervalSince1970: inbox.at / 1000).formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
            }
            Text("Your Gym Check-in Shortcut reads Health data (sleep, HRV, VO₂max, calories…) and uploads it to your data repo; the app collects it on every sync and pre-fills your check-in.")
                .font(Theme.body(12.5)).foregroundStyle(Theme.muted)
        }
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Theme.head(17, weight: .bold)).foregroundStyle(Theme.text)
                        if let status { Text(status).font(Theme.mono(12)).foregroundStyle(statusColor ?? Theme.muted).multilineTextAlignment(.leading) }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(open.contains(id) ? 180 : 0)).foregroundStyle(Theme.muted)
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
