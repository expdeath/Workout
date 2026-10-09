import SwiftUI
import UniformTypeIdentifiers

/// Ports src/screens/Settings.jsx — a profile card, then grouped rows
/// (preferences, devices, data & account); each row opens its form in a
/// sheet: AI coach setup (+ the shared Gemini key, owner only), weekly
/// target, Apple Health, plates & bar, GitHub backup, your data
/// (export / CSV / import / clear), feedback, about. Sign out at the end.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var detail: String?
    @State private var prefsTick = 0 // re-read Prefs after a switch flips
    // Delete account: type DELETE, then a fresh sign-in proves it's you
    @State private var deleteTyped = ""
    @State private var deleting = false
    @State private var deleteMsg = ""
    @State private var target = Dashboard.weeklyTarget(LocalStore.shared.backup.aiSettings)
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
    @State private var signOutMsg = ""
    // apple health
    @State private var healthBusy = false
    @State private var healthMsg = ""

    private var account: Cloud.AccountInfo? { Account.current() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TabHeader(title: "Settings")
                if account != nil { profileCard }

                group("Preferences", note: "Coach logic") {
                    SettingsRow(icon: "crown", tint: Cloud.shared.proActive ? Theme.green : Theme.amberText, title: "COACH Pro",
                                subtitle: Cloud.shared.proActive ? (Cloud.shared.proTrial ? "Active · free trial" : "Active") : "AI coach with no key to set up · 7 days free") { detail = "pro" }
                    SettingsRow(icon: "brain.head.profile", title: "AI Coach", subtitle: coachStatus) { detail = "coach" }
                    SettingsRow(icon: "bell.badge", title: "Alerts & reports", subtitle: alertsStatus) { detail = "alerts" }
                    SettingsRow(icon: "target", tint: Theme.green, title: "Weekly target", subtitle: "Streak, consistency and the target bar") { detail = "target" } trailing: {
                        Text("\(Dashboard.weeklyTarget(LocalStore.shared.backup.aiSettings))/wk").capsLabel(Theme.amberText, size: 14)
                    }
                }

                group("Devices & sensors", note: watchStatus.hasPrefix("Synced") ? "All synced" : nil) {
                    SettingsRow(icon: "applewatch", tint: Theme.green, title: "Apple Watch & Health", subtitle: watchStatus) { detail = "watch" }
                    SettingsRow(icon: "scalemass", title: "Barbell & plate setup", subtitle: plateSummary) { detail = "gym" } trailing: {
                        Text("\(Helpers.fmtKg(Double(barKg) ?? Helpers.defaultBarKg))kg bar").capsLabel(Theme.textBody, size: 13)
                    }
                }

                group("Data & account", note: "Cloud vault") {
                    SettingsRow(icon: "icloud", tint: Theme.green, title: "Cloud backup", subtitle: backupStatus) { detail = "sync" }
                    SettingsRow(icon: "square.and.arrow.up", title: "Export workout log", subtitle: "CSV · JSON backup · import") { detail = "data" }
                    if account != nil {
                        SettingsRow(icon: "bubble.left.and.text.bubble.right", title: "Send feedback", subtitle: "Straight to Abhi") { detail = "account" }
                    }
                    SettingsRow(icon: "info.circle", tint: Theme.muted, title: "About COACH", subtitle: nil) { detail = "about" }
                }

                if account != nil {
                    Button {
                        if confirmOut {
                            Task {
                                if let refusal = await appState.signOut() {
                                    signOutMsg = refusal
                                    confirmOut = false
                                }
                            }
                        } else { confirmOut = true }
                    } label: {
                        Label(confirmOut ? "Tap again — this wipes this device" : "Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle(color: Theme.red))
                    if !signOutMsg.isEmpty { Text(signOutMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amberText) }
                    Text("Signing out clears this device, including exercise photos. Your log stays in the cloud.")
                        .font(Theme.body(12.5)).foregroundStyle(Theme.dim)
                    Button { detail = "delete" } label: { Label("Delete account", systemImage: "trash") }
                        .font(Theme.body(14, weight: .medium)).foregroundStyle(Theme.red).padding(.top, 6)
                }
                Text("COACH · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                    .capsLabel(Theme.dim, size: 11).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .coachScreen()
        .onAppear { if !Cloud.shared.aiReady { detail = "coach" } }
        .task { eventCount = await Cloud.shared.countEvents() }
        .sheet(item: $detail) { id in detailSheet(id) }
    }

    // MARK: - Profile + groups

    private var profileCard: some View {
        Button { appState.sheet = .profile } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: appState.displayName, size: 54)
                    Circle().fill(Theme.green).frame(width: 12, height: 12).overlay(Circle().stroke(Theme.bgCard, lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(appState.displayName).font(Theme.body(18, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                        if account?.admin == true { Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(Theme.amberText) }
                    }
                    HStack(spacing: 6) {
                        StatusPill(text: account?.admin == true ? "Admin" : "Member", color: Theme.amberText, dot: false)
                        Text(account?.email ?? "").font(Theme.meta(12.5)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 38, height: 38).background(Theme.bgHigh).clipShape(Circle())
            }
            .padding(14)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit profile")
    }

    private func group(_ title: String, note: String?, @ViewBuilder _ rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: title, trailing: note, trailingColor: note == "All synced" ? Theme.green : Theme.muted)
                .padding(.horizontal, 4)
            RowGroup { rows() }
        }
    }

    private static let titles = ["coach": "AI Coach", "target": "Weekly target", "watch": "Apple Health", "gym": "Plates & Bar",
                                 "sync": "Cloud backup", "data": "Your data", "account": "Feedback", "about": "About", "alerts": "Alerts & reports", "delete": "Delete account", "pro": "COACH Pro"]

    private func detailSheet(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Self.titles[id] ?? "").font(Theme.head(26, weight: .bold)).textCase(.uppercase).tracking(0.6)
                Spacer()
                IconButton(icon: "xmark", label: "Close") { detail = nil }
            }
            .padding(.horizontal, 20).padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch id {
                    case "coach": coachSection
                    case "target": targetSection
                    case "watch": watchSection
                    case "gym": gymSection
                    case "sync": backupSection
                    case "data": dataSection
                    case "account": accountSection
                    case "alerts": alertsSection
                    case "delete": deleteSection
                    case "pro": ProSectionView()
                    default:
                        Text("COACH plans each session with Google Gemini from your check-in, history and recovery data. Your log lives in Firestore, backed up to your GitHub repo.")
                            .font(Theme.body(14)).foregroundStyle(Theme.muted)
                        HStack(spacing: 16) {
                            Link("Privacy policy", destination: Subscriptions.privacyURL)
                            Link("Terms of service", destination: Subscriptions.termsURL)
                        }
                        .font(Theme.body(14)).tint(Theme.amberText)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .coachScreen()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
    }

    // MARK: - Row statuses

    private var coachStatus: String {
        _ = prefsTick
        if !AIConsent.allowed { return "Off — nothing is sent to Google Gemini" }
        if Cloud.shared.proActive { return "Ready · COACH Pro" }
        return Cloud.shared.geminiKey.isEmpty
            ? (Cloud.shared.canSetGeminiKey ? "No API key yet — add one to start" : "No API key yet — ask Abhi")
            : (LocalStore.shared.backup.aiSettings.profile.isEmpty ? "Ready · add your profile" : "Ready · profile set")
    }

    private var watchStatus: String {
        if LocalStore.shared.backup.health.contains(where: { $0.date == Helpers.todayStr() }) { return "Synced today" }
        return HealthKitSync.requested ? "Connected · nothing today yet" : "Not connected"
    }

    private var plateSummary: String {
        (Helpers.parsePlates(plates) ?? Helpers.defaultPlates).map(Helpers.fmtKg).joined(separator: " / ") + " kg plates"
    }

    private var backupStatus: String {
        let last = GitHubSync.lastSync()
        if last?.status == "ok", let at = ISO8601DateFormatter.withMillis.date(from: last!.at) ?? ISO8601DateFormatter().date(from: last!.at) {
            return "Live sync · backed up \(at.formatted(date: .abbreviated, time: .shortened))"
        }
        if last?.status == "error" { return "Backup failed: \(last?.message ?? "")" }
        return repo.isEmpty || token.isEmpty ? "Live sync · no GitHub backup" : "Live sync · backup pending"
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            QLabel(text: "Sessions per week", value: "\(target)")
            Stepper("Weekly target", value: $target, in: 1...14).labelsHidden()
            Text("Your streak counts weeks that hit this, and Progress measures consistency against it.")
                .font(Theme.body(13.5)).foregroundStyle(Theme.muted)
            Button("Save target") {
                LocalStore.shared.updateAISettings { $0.weeklyTarget = target }
                LocalStore.shared.logEvent(type: "weekly_target_saved", data: ["target": .number(Double(target))])
                detail = nil
            }
            .buttonStyle(BigButtonStyle()).padding(.top, 10)
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            QLabel(text: "Send feedback to Abhi")
            TextField("", text: Binding(get: { feedback }, set: { feedback = String($0.prefix(2000)) }),
                      prompt: Text("Bugs, ideas, anything…").foregroundStyle(Theme.dim), axis: .vertical)
                .lineLimit(3...8).coachInput()
            Button(sendingFb ? "Sending…" : "Send feedback") { Task { await sendFeedback() } }
                .buttonStyle(BigButtonStyle())
                .disabled(sendingFb || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !feedbackMsg.isEmpty { Text(feedbackMsg).font(Theme.body(13.5)).foregroundStyle(Theme.amberText) }
        }
    }

    private var coachSection: some View {
        return section {
            Toggle(isOn: Binding(
                get: { _ = prefsTick; return AIConsent.allowed },
                set: { on in
                    AIConsent.set(on)
                    prefsTick += 1
                    LocalStore.shared.logEvent(type: "ai_consent", data: ["allowed": .bool(on), "from": .string("settings")])
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use the AI coach (Google Gemini)").font(Theme.body(15, weight: .medium))
                    Text(AIConsent.allowed
                         ? "Sends your workouts, check-ins, chats and Health data to Google Gemini to plan sessions."
                         : "Off — nothing goes to Gemini. You can still log workouts and run saved ones as written.")
                        .font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.amber)
            if AIConsent.allowed {
                DisclosureGroup("What's shared") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(AIConsentView.shared, id: \.title) { item in
                            (Text(item.title).bold() + Text(" — \(item.sub)")).font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(Theme.body(13.5)).tint(Theme.amberText)
            }
            if Cloud.shared.canSetGeminiKey {
                QLabel(text: account?.selfServe == true ? "Your Gemini API key" : "Gemini API key (shared)")
                HStack {
                    Group {
                        if showKey { TextField("", text: $key, prompt: Text("AIzaSy…").foregroundStyle(Theme.dim)) }
                        else { SecureField("", text: $key, prompt: Text("AIzaSy…").foregroundStyle(Theme.dim)) }
                    }
                    .textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }.font(Theme.meta(13)).foregroundStyle(Theme.muted)
                }
                Text("\(account?.selfServe == true ? "Only your account uses it." : "Shared by everyone you invited.") Free at aistudio.google.com/apikey.")
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
                let newKey = key.trimmingCharacters(in: .whitespaces)
                if Cloud.shared.canSetGeminiKey, newKey != Cloud.shared.geminiKey {
                    if account?.selfServe == true { Cloud.shared.setOwnGeminiKey(newKey) }
                    else { Cloud.shared.setSharedGeminiKey(newKey) }
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
        return section {
            Text(backupStatus).font(Theme.meta(13.5)).foregroundStyle(Theme.green)
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
        }
    }

    private var dataSection: some View {
        section {
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
        section {
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
        return section {
            Text(watchStatus).font(Theme.meta(13.5)).foregroundStyle(watchStatus == "Synced today" ? Theme.green : Theme.muted)
            if let text {
                Text("Today: \(Stats.fmtHealthLine(Stats.parseHealthNumbers(text)).isEmpty ? text : Stats.fmtHealthLine(Stats.parseHealthNumbers(text)))")
                    .font(Theme.body(14)).foregroundStyle(Theme.green)
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

    /// The body of one settings sheet.
    // MARK: - Delete account (App Store guideline 5.1.1(v))

    private var deleteSection: some View {
        section {
            Text("This permanently deletes your COACH account and everything in it:").font(Theme.body(14.5))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(["every logged session, set and personal record",
                         "Apple Health / Watch data, check-ins, coach chats and reports",
                         "saved workouts, settings, your Gemini key and GitHub token",
                         "your sign-in — signing in again starts a brand-new, empty account"], id: \.self) {
                    Text("• \($0)").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                }
            }
            Text("Your GitHub backup repository is yours and isn't touched — delete it on github.com if you want it gone too. You'll sign in once more to confirm it's you.")
                .font(Theme.meta(12.5)).foregroundStyle(Theme.dim)
            QLabel(text: "Type DELETE to confirm")
            TextField("", text: $deleteTyped).textInputAutocapitalization(.characters).autocorrectionDisabled().coachInput()
            if !deleteMsg.isEmpty { ErrorBox(text: deleteMsg) }
            Button(deleting ? "Deleting…" : "Delete my account") {
                Task {
                    deleting = true
                    deleteMsg = ""
                    if let err = await appState.deleteAccount() { deleteMsg = err } else { detail = nil }
                    deleting = false
                }
            }
            .buttonStyle(BigButtonStyle(danger: true))
            .disabled(deleting || deleteTyped.trimmingCharacters(in: .whitespaces) != "DELETE")
            .opacity(deleting || deleteTyped.trimmingCharacters(in: .whitespaces) != "DELETE" ? 0.5 : 1)
        }
    }

    // MARK: - Alerts & reports (account state `prefs`, shared with the web app)

    private static let prefRows: [(group: String, rows: [(key: String, title: String, sub: String)])] = [
        ("Rest timer", [
            ("restSound", "Sound", "A chime when the rest ends"),
            ("restVibrate", "Vibration", "A buzz when the rest ends"),
            ("restNotify", "Notification", "Alert when the phone is locked or you're in another app"),
        ]),
        ("During a workout", [
            ("keepAwake", "Keep screen awake", "The screen stays on while you rest"),
        ]),
        ("AI reports", [
            ("weeklyReview", "Weekly review", "Written every Sunday from your week"),
            ("monthlyReport", "Monthly report", "Written in the first week of a new month"),
            ("debrief", "Post-workout debrief", "Two sentences from the coach after each session"),
        ]),
    ]

    private var alertsStatus: String {
        _ = prefsTick
        let on = Self.prefRows.flatMap(\.rows).filter { Prefs.isOn($0.key) }.count
        return "\(on) of 7 on · rest timer, screen, AI reports"
    }

    private var alertsSection: some View {
        section {
            ForEach(Self.prefRows, id: \.group) { g in
                QLabel(text: g.group)
                ForEach(g.rows, id: \.key) { r in
                    Toggle(isOn: Binding(
                        get: { _ = prefsTick; return Prefs.isOn(r.key) },
                        set: { on in
                            Prefs.set(r.key, on)
                            prefsTick += 1
                            LocalStore.shared.logEvent(type: "pref_changed", data: ["key": .string(r.key), "on": .bool(on)])
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(Theme.body(15, weight: .medium))
                            Text(r.sub).font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.amber)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
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
