import Foundation
import UIKit
import FirebaseAuth
import AuthenticationServices

/// Mirrors the screen state machine in src/App.jsx — one enum case per
/// screen the JS `useState('screen')` can hold.
enum Screen: Equatable {
    case loading
    case login
    case home
    case checkIn
    case generating
    case workout
    case finish
    case history
    case historyDetail
    case addPast
    case records
    case progress
    case settings
    case workouts
    case aiConsent
}

/// App-wide sheets opened from the tab header.
enum AppSheet: String, Identifiable {
    case notifications, profile, search
    var id: String { rawValue }
}

struct SyncInfo: Equatable {
    var state: String // "syncing" | "ok" | "error"
    var at: Date?
    var sessions: Int?
    var message: String?
}

struct WeeklyReviewCache: Codable {
    var week: String
    var at: Double
    var text: String
    var count: Int
    var progressions: String
}

struct MonthlyReportCache: Codable {
    var month: String
    var at: Double
    var text: String
    var sum: Stats.MonthSummary
}

/// Root app state — ports the state + effects in src/App.jsx onto a
/// single observable object driving RootView's screen switch. Web-only
/// concerns (URL hash health ingestion, invite magic-link boot parsing,
/// visibility-change listeners) are left out; everything else — the
/// daily check-in → AI plan → workout → finish loop, sync orchestration,
/// weekly/monthly report generation — is ported.
/// Main-actor isolated: every mutation of app state (and of LocalStore,
/// also main-actor) happens on the main thread — an AI reply finishing on
/// a background thread must never race a Firestore snapshot updating the
/// same session list (that race once lost a debrief).
@MainActor
@Observable
final class AppState {
    var screen: Screen = .loading {
        didSet {
            #if DEBUG
            if ProcessInfo.processInfo.environment["COACH_DEBUG_TRACE"] == "1" {
                print("[COACH] screen \(oldValue) → \(screen) · instance \(ObjectIdentifier(self).hashValue % 10000)")
                Thread.callStackSymbols.prefix(6).forEach { print("   ", $0) }
            }
            #endif
        }
    }
    var history: [Session] = []
    var todayPlan: Session? = nil
    var chatOpen = false
    var sheet: AppSheet? = nil
    /// When the notification inbox was last opened (ms) — state `notifSeenAt`.
    var notifSeenAt: Double = 0
    /// Name the user chose in Edit profile — state `displayName` (shared
    /// with the web app); falls back to the Google account name.
    var displayNameOverride: String? = nil
    var detailSession: Session? = nil
    var error = ""
    var statusMsg = ""
    var syncInfo: SyncInfo? = nil
    var weeklyReview: WeeklyReviewCache? = nil
    var monthlyReport: MonthlyReportCache? = nil
    var loginError = ""
    /// Bumped when account state changes (another device saved a workout…),
    /// so screens that read it straight from Cloud re-render.
    var stateTick = 0
    /// My workouts: where its back button returns to, and a workout to open straight away.
    var workoutsFrom: Screen = .home
    var workoutsOpenId: String? = nil
    /// Search → Records: the exercise to select (changes each time).
    var recordPick: RecordPick? = nil
    struct RecordPick: Equatable { var name: String; var at = Date() }

    var ci = Checkin()
    var fin = FinishInfo()
    /// Lives here, not in WorkoutView, so a set ticked on the Watch starts
    /// it too and the Watch shows the same countdown.
    var rest: RestTimer?

    /// The rest timer between sets. `fromWatch`: started by a set logged on
    /// the Watch — the Watch taps the wrist, so the iPhone stays quiet.
    struct RestTimer: Equatable {
        var endsAt: Date
        var total: Double
        var exName: String
        var fromWatch = false
    }

    var muscleGap: (group: String, lastDaysAgo: Int)? { Stats.biggestMuscleGap(history) }

    private var lastSyncAt: Date = .distantPast
    private var periodicSync: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    init() {
        Task { @MainActor in await start() }
    }

    // MARK: - Sign-in + boot

    /// Restores the Google session and opens the account, or shows Login.
    @MainActor
    func start() async {
        #if DEBUG
        if Cloud.shared.offline { await boot(); return }
        // automation only: sign in with a Firebase custom token minted by
        // an admin script (no Google UI) — compiled out of Release builds
        if let token = ProcessInfo.processInfo.environment["COACH_DEBUG_CUSTOM_TOKEN"], !token.isEmpty {
            _ = try? await Auth.auth().signIn(withCustomToken: token)
        }
        #endif
        do {
            if try await Account.resume() != nil {
                await boot()
            } else {
                screen = .login
            }
        } catch {
            if case Cloud.CloudError.blocked = error { await Cloud.shared.signOut() }
            loginError = Self.message(for: error)
            screen = .login
        }
    }

    /// Login screen → Google → allowlist (sign-up on first visit) → account.
    @MainActor
    func signIn() async {
        loginError = ""
        do {
            _ = try await Account.signIn()
            screen = .loading
            await boot()
        } catch {
            // closing Google's sheet isn't an error worth showing
            if (error as NSError).domain == "com.google.GIDSignIn", (error as NSError).code == -5 { return }
            loginError = Self.message(for: error)
        }
    }

    /// The Sign in with Apple button finished (LoginView).
    @MainActor
    func signInWithApple(_ result: Result<ASAuthorization, Error>, nonce: String) async {
        loginError = ""
        do {
            let auth = try result.get()
            _ = try await Account.signInWithApple(AppleSignIn.result(from: auth, rawNonce: nonce))
            screen = .loading
            await boot()
        } catch {
            if (error as? ASAuthorizationError)?.code == .canceled { return } // closed Apple's sheet
            loginError = Self.message(for: error)
        }
    }

    /// Settings → Delete account. Returns why it failed (nothing deleted
    /// when the re-sign-in is cancelled), or nil — then we're at Login.
    @MainActor
    func deleteAccount() async -> String? {
        do {
            await Subscriptions.stop()
            try await Account.deleteAccount()
        } catch {
            if (error as? ASAuthorizationError)?.code == .canceled { return "Cancelled — nothing was deleted." }
            if (error as NSError).domain == "com.google.GIDSignIn", (error as NSError).code == -5 { return "Cancelled — nothing was deleted." }
            if (error as NSError).code == AuthErrorCode.userMismatch.rawValue { return "That was a different account — sign in as the one you want to delete." }
            return error.localizedDescription
        }
        history = []
        todayPlan = nil
        weeklyReview = nil
        monthlyReport = nil
        screen = .login
        return nil
    }

    /// The consent screen was answered — on to the app.
    func aiConsentAnswered(_ allowed: Bool) {
        AIConsent.set(allowed)
        LocalStore.shared.logEvent(type: "ai_consent", data: ["allowed": .bool(allowed)])
        screen = Cloud.shared.aiReady ? .home : .settings
    }

    /// Signs out only once everything logged on this device is in the
    /// cloud — signing out clears the device's offline copy, so unsynced
    /// changes would be lost. Returns why it refused, or nil.
    @MainActor
    func signOut() async -> String? {
        LocalStore.shared.logEvent(type: "signed_out", data: [:])
        guard await Cloud.shared.flushWrites() else {
            return "Some changes haven't reached the cloud yet (no connection?). Connect to the internet and try again — signing out now would lose them."
        }
        await Subscriptions.stop()
        await Account.signOut()
        history = []
        todayPlan = nil
        weeklyReview = nil
        monthlyReport = nil
        screen = .login
        return nil
    }

    private static func message(for error: Error) -> String {
        if let e = error as? Cloud.CloudError { return e.localizedDescription }
        return "Couldn't open your account — check your connection and try again."
    }

    func boot() async {
        if let acct = Account.current()?.accountId { Task { await Subscriptions.start(accountId: acct) } }
        Cloud.shared.onChange = { [weak self] what in self?.cloudChanged(what) }
        adoptLegacyDeviceSettings()
        loadActive()
        loadStateFromCloud()
        WatchSync.shared.publish(force: true)
        pruneOldHealthText()
        LocalStore.shared.logEvent(type: "app_open", data: ["sessions": .number(Double(history.count))])
        HealthIngest.reparseRows() // parser upgrades backfill old rows
        Task {
            await HealthKitSync.shared.sync() // today + any missing days of the last week
            await runSync()
        }
        // and every 5 minutes while the app stays open (throttled like a foreground return)
        periodicSync?.cancel()
        periodicSync = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if UIApplication.shared.applicationState == .active, Cloud.shared.account != nil { self.maybeSyncOnForeground() }
            }
        }
        Task { await maybeWeeklyReview() }
        Task { await maybeMonthlyReport() }
        // asked once per account before anything goes to Gemini; then, with
        // no API key yet, Settings first
        screen = !AIConsent.answered ? .aiConsent : Cloud.shared.aiReady ? .home : .settings
        #if DEBUG
        if let s = DebugSeed.startScreen {
            ci = buildDefaultCheckin() // what Home's "Start check-in" tap does
            screen = s
        }
        #endif
    }

    /// Deleted sessions are already excluded — LocalStore.hardDelete
    /// removes the row for real (see src/db/db.js's tombstone comment).
    private func loadActive() {
        history = LocalStore.shared.backup.sessions.sorted { ($0.date + $0.id) < ($1.date + $1.id) }
    }

    private func persistToday(_ t: Session?) {
        todayPlan = t
        Cloud.shared.setState("today", t.flatMap { try? JSONValue.encoding($0) })
        WatchSync.shared.publish()
    }

    // MARK: - Cloud state (shared with the web app, same keys)

    private func decodeState<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let v = Cloud.shared.stateValue(key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(v))
    }

    /// A field of a state object without decoding the whole thing — so a
    /// report the web app wrote is recognised even if a field's type differs.
    private func stateField(_ key: String, _ field: String) -> String? {
        guard case .object(let o)? = Cloud.shared.stateValue(key), case .string(let s)? = o[field] else { return nil }
        return s
    }

    private func loadStateFromCloud() {
        let t = decodeState(Session.self, "today")
        todayPlan = t?.date == Helpers.todayStr() ? t : nil
        weeklyReview = decodeState(WeeklyReviewCache.self, "weeklyReview")
        monthlyReport = decodeState(MonthlyReportCache.self, "monthlyReport")
        if case .number(let n)? = Cloud.shared.stateValue("notifSeenAt") { notifSeenAt = n }
        if case .string(let n)? = Cloud.shared.stateValue("displayName"), !n.isEmpty { displayNameOverride = n } else { displayNameOverride = nil }
    }

    // MARK: - Profile + notifications

    var displayName: String {
        displayNameOverride ?? Account.current().map { $0.name.isEmpty ? $0.email : $0.name } ?? ""
    }

    var firstName: String? {
        displayName.split(separator: " ").first.map(String.init)
    }

    func setDisplayName(_ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        displayNameOverride = n.isEmpty ? nil : n
        Cloud.shared.setState("displayName", n.isEmpty ? nil : .string(n))
    }

    var notifications: [Dashboard.Notice] {
        Dashboard.notifications(history, weekly: weeklyReview, monthly: monthlyReport)
    }

    var unreadNotifications: Int { notifications.filter { $0.at > notifSeenAt }.count }

    func markNotificationsSeen() {
        notifSeenAt = (Date().timeIntervalSince1970 * 1000).rounded()
        Cloud.shared.setState("notifSeenAt", .number(notifSeenAt))
    }

    /// Another device (or this one) changed the account.
    private func cloudChanged(_ what: String) {
        switch what {
        case "sessions": loadActive()
        case "state": loadStateFromCloud(); stateTick += 1; WatchSync.shared.publish()
        case "pro": stateTick += 1
        default: break
        }
    }

    /// Drop single-use Watch text from earlier days (pruneOldHealth on the web).
    private func pruneOldHealthText() {
        let today = "healthText-\(Helpers.todayStr())"
        for k in Cloud.shared.stateKeys() where k.hasPrefix("healthText-") && k != today {
            Cloud.shared.setState(k, nil)
        }
    }

    /// One-time handover from the invite-code era: a Gemini key or GitHub
    /// token this device still holds fills the cloud copy if it's missing
    /// (key: owner only; token: only for this account's repo). Never
    /// overwrites; the old secrets are removed afterwards.
    private func adoptLegacyDeviceSettings() {
        guard let acct = Cloud.shared.account else { return }
        if let key = Keychain.get("gemini-api-key"), !key.isEmpty, acct.admin, Cloud.shared.geminiKey.isEmpty {
            Cloud.shared.setSharedGeminiKey(key)
        }
        let cfg = GitHubSync.config()
        if let token = Keychain.get("gh-token"), !token.isEmpty, cfg.token.isEmpty,
           !cfg.repo.isEmpty, Defaults.string("gh-repo")?.lowercased() == cfg.repo.lowercased() {
            GitHubSync.setConfig(token: token, repo: cfg.repo)
        }
        Keychain.removeAll()
    }

    // MARK: - Sync

    @discardableResult
    func runSync(replaceRemote: Bool = false) async -> GitHubSync.Result? {
        lastSyncAt = Date()
        syncInfo = SyncInfo(state: "syncing")
        do {
            let r = try await GitHubSync.syncNow(force: replaceRemote)
            if r.status == .unconfigured {
                syncInfo = nil
                return r
            }
            if r.changedLocal { loadActive() }
            syncInfo = SyncInfo(state: "ok", at: Date(), sessions: r.sessions)
            return r
        } catch {
            LocalStore.shared.logEvent(type: "sync_failed", data: ["message": .string(error.localizedDescription)])
            syncInfo = SyncInfo(state: "error", message: error.localizedDescription)
            syncTask?.cancel()
            syncTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await runSync()
            }
            return nil
        }
    }

    /// Call when the app regains focus/foreground — throttled to 20s.
    func maybeSyncOnForeground() {
        guard Date().timeIntervalSince(lastSyncAt) >= 20 else { return }
        Task {
            await HealthKitSync.shared.sync() // Apple Health → today's row (no-op until connected)
            await runSync()
        }
    }

    /// Home's Start check-in / Quick start: fresh Apple Health numbers
    /// for today first, so the check-in is pre-filled with them.
    func prepareCheckin() async -> Checkin {
        await HealthKitSync.shared.sync(days: 1)
        // nothing for today yet: Watch data copied to the clipboard fills it in
        // (as on the web). Only read when the clipboard holds numbers — the
        // pattern check doesn't trigger iOS's paste prompt.
        if (todaysHealth() ?? "").isEmpty, UIPasteboard.general.hasStrings,
           let found = try? await UIPasteboard.general.detectedPatterns(for: [\.number]), found.contains(\UIPasteboard.DetectedValues.number),
           HealthIngest.looksLikeHealthData(UIPasteboard.general.string) {
            let t = HealthIngest.storeToday(UIPasteboard.general.string ?? "")
            LocalStore.shared.logEvent(type: "health_pasted_auto", data: ["chars": .number(Double(t.count))])
        }
        return buildDefaultCheckin()
    }

    // MARK: - Check-in defaults

    func buildDefaultCheckin() -> Checkin {
        var c = Checkin()
        c.health = todaysHealth()
        // the saved-workout library: today's scheduled workout + add-ons
        let today = Workouts.scheduledFor()
        c.templateId = today.sessions.first?.id ?? ""
        c.addOnIds = today.addOns.map(\.id)
        return c
    }

    // MARK: - My workouts

    func openWorkouts(from: Screen? = nil, id: String? = nil) {
        let f = from ?? screen
        workoutsFrom = [.home, .history, .progress, .records, .settings, .checkIn].contains(f) ? f : .home
        workoutsOpenId = id
        screen = .workouts
    }

    /// Start a saved workout: the check-in, with it already picked.
    func startSavedWorkout(_ id: String) async {
        var c = await prepareCheckin()
        c.templateId = id
        ci = c
        error = ""
        screen = .checkIn
    }

    func openRecord(_ name: String) {
        recordPick = RecordPick(name: name)
        screen = .records
    }

    /// Today's health row (from the Watch-shortcut inbox, drained on
    /// sync) formatted for the check-in — mirrors todaysHealth() in
    /// src/utils/healthIngest.js's common case (the URL-hash /
    /// clipboard paths are web-only).
    private func todaysHealth() -> String? {
        if case .string(let t)? = Cloud.shared.stateValue("healthText-\(Helpers.todayStr())"), !t.isEmpty { return t }
        return LocalStore.shared.backup.health.first(where: { $0.date == Helpers.todayStr() })?.raw
    }

    // MARK: - AI plan generation

    func generateWorkout(_ checkin: Checkin) async {
        screen = .generating
        error = ""
        statusMsg = ""
        LocalStore.shared.logEvent(type: "checkin_submitted", data: [:])

        if let bodyKg = Double(checkin.bodyKg), bodyKg > 20, bodyKg < 300 {
            LocalStore.shared.mergeHealth(HealthRow(date: Helpers.todayStr(), weightKg: bodyKg))
        }

        // a saved workout (yours or your trainer's) and today's add-ons
        let template = Workouts.get(checkin.templateId)
        let addOns = checkin.addOnIds.compactMap { Workouts.get($0) }

        do {
            var plan: Plan
            do {
                plan = try await Gemini.generateWorkoutPlan(checkin: checkin, history: history, template: template) { [weak self] msg in
                    Task { @MainActor in self?.statusMsg = msg }
                }
                if let template, !template.adapt { plan = Workouts.enforceExact(plan, template, history) }
                else if let template { plan.fromWorkout = Workouts.fromWorkout(template, adapt: true) }
            } catch {
                guard let template else { throw error }
                // the coach is unreachable — a saved workout still runs, as written
                LocalStore.shared.logEvent(type: "generation_failed", data: ["message": .string(error.localizedDescription), "fallback": .string("saved workout")])
                plan = Workouts.templateToPlan(template, history)
                plan.concerns = "Coach unavailable — weights are from your history."
            }
            plan = Workouts.appendAddOns(plan, addOns, history)
            LocalStore.shared.logEvent(type: "plan_generated", data: [
                "sessionType": .string(plan.sessionType), "title": .string(plan.title),
                "estTimeMin": .number(Double(plan.estTimeMin)),
                "workout": template.map { .string($0.id) } ?? .null, "addOns": .number(Double(addOns.count)),
            ])
            let log = plan.exercises.map { ex in Array(repeating: SetLog(), count: ex.sets > 0 ? ex.sets : 3) }
            let t = Session(
                id: "\(Helpers.todayStr())#\(Int(Date().timeIntervalSince1970 * 1000))",
                date: Helpers.todayStr(), startedAt: Date().timeIntervalSince1970 * 1000,
                checkin: checkin, plan: plan, log: log, finished: false
            )
            persistToday(t)
            screen = .workout
            WatchSync.shared.workoutStarted(sessionType: plan.sessionType)
        } catch {
            LocalStore.shared.logEvent(type: "generation_failed", data: ["message": .string(error.localizedDescription)])
            self.error = error.localizedDescription.isEmpty
                ? "Couldn't build today's session. Check Settings for your API key, then try again."
                : error.localizedDescription
            screen = .checkIn
        }
    }

    // MARK: - Weekly / monthly reports

    private func maybeWeeklyReview() async {
        guard Prefs.isOn("weeklyReview") else { return } // switched off in Settings
        guard Calendar.current.component(.weekday, from: Date()) == 1 else { return } // Sundays only (1 = Sunday)
        let thisMonday = Stats.mondayOf(Helpers.todayStr())
        guard stateField("weeklyReview", "week") != thisMonday else { return } // already done this week
        guard let summary = Stats.lastWeekSummary(history), Cloud.shared.aiReady else { return }
        guard let text = try? await Gemini.generateWeeklyReview(summary) else { return }
        let review = WeeklyReviewCache(week: thisMonday, at: (Date().timeIntervalSince1970 * 1000).rounded(), text: text, count: summary.count, progressions: summary.progressions)
        Cloud.shared.setState("weeklyReview", try? JSONValue.encoding(review))
        weeklyReview = review
    }

    private func maybeMonthlyReport() async {
        guard Prefs.isOn("monthlyReport") else { return } // switched off in Settings
        let now = Date()
        let cal = Calendar.current
        guard cal.component(.day, from: now) <= 7 else { return } // first week of the month only
        guard let prevMonthDate = cal.date(byAdding: .month, value: -1, to: now) else { return }
        let ym = "\(cal.component(.year, from: prevMonthDate))-\(String(format: "%02d", cal.component(.month, from: prevMonthDate)))"
        guard stateField("monthlyReport", "month") != ym else { return } // already generated
        guard Cloud.shared.aiReady else { return }
        guard let sum = Stats.monthSummary(history, LocalStore.shared.backup.health, ym: ym) else { return }
        guard let text = try? await Gemini.generateMonthlyReport(sum) else { return }
        let report = MonthlyReportCache(month: ym, at: (Date().timeIntervalSince1970 * 1000).rounded(), text: text, sum: sum)
        Cloud.shared.setState("monthlyReport", try? JSONValue.encoding(report))
        monthlyReport = report
    }

    // MARK: - Mid-workout plan edits

    func swapExercise(_ exI: Int) {
        guard var t = todayPlan, exI < t.plan.exercises.count else { return }
        let ex = t.plan.exercises[exI]
        guard !ex.alt.isEmpty else { return }
        t.plan.exercises[exI].name = ex.alt
        t.plan.exercises[exI].alt = ex.name
        LocalStore.shared.logEvent(type: "exercise_swapped", data: ["from": .string(ex.name), "to": .string(ex.alt)])
        persistToday(t)
    }

    func renameExercise(_ exI: Int, _ name: String) {
        guard var t = todayPlan, exI < t.plan.exercises.count else { return }
        let ex = t.plan.exercises[exI]
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !clean.isEmpty, clean.lowercased() != ex.name.trimmingCharacters(in: .whitespaces).lowercased() else { return }
        t.plan.exercises[exI].name = clean
        t.plan.exercises[exI].alt = ex.name
        t.plan.exercises[exI].suggestedWeight = ""
        LocalStore.shared.logEvent(type: "exercise_swapped_custom", data: ["from": .string(ex.name), "to": .string(clean)])
        persistToday(t)
    }

    func removeExercise(_ exI: Int) {
        guard var t = todayPlan, exI < t.plan.exercises.count else { return }
        let ex = t.plan.exercises[exI]
        t.plan.exercises.remove(at: exI)
        if exI < t.log.count { t.log.remove(at: exI) }
        t.plan.estTimeMin = max(t.plan.estTimeMin - 6, 15)
        LocalStore.shared.logEvent(type: "exercise_removed", data: ["name": .string(ex.name)])
        persistToday(t)
    }

    /// Removing only pops the last row while it's still empty — logged
    /// work can't be deleted this way.
    func adjustSets(_ exI: Int, _ delta: Int) {
        guard var t = todayPlan, exI < t.log.count else { return }
        var rows = t.log[exI]
        guard !rows.isEmpty else { return }
        if delta < 0, rows.count > 1, !rows.last!.isLogged {
            rows.removeLast()
        } else if delta > 0 {
            rows.append(SetLog())
        } else {
            return
        }
        t.log[exI] = rows
        if exI < t.plan.exercises.count { t.plan.exercises[exI].sets = rows.count }
        LocalStore.shared.logEvent(type: "sets_adjusted", data: ["delta": .number(Double(delta)), "sets": .number(Double(rows.count))])
        persistToday(t)
    }

    func updateSet(_ exI: Int, _ setI: Int, weight: String? = nil, reps: String? = nil, time: String? = nil, dist: String? = nil, done: Bool? = nil, effort: String? = nil) {
        guard var t = todayPlan, exI < t.log.count, setI < t.log[exI].count else { return }
        var s = t.log[exI][setI]
        // clamp, don't reject — same sanitation as the web app's updateSet
        if let weight { s.weight = Helpers.cleanWeight(weight) }
        if let reps { s.reps = Helpers.cleanReps(reps) }
        if let time { s.time = Helpers.cleanTime(time) }
        if let dist { s.dist = Helpers.cleanDist(dist) }
        if let done { s.done = done }
        if let effort { s.effort = effort }
        t.log[exI][setI] = s
        persistToday(t)
    }

    /// AI "make it harder" upgrade applied to today's plan.
    /// add = new exercise · extraSet = +1 set · replace = harder variation
    func applyHarder(_ opt: Gemini.IntensifyOption) -> Bool {
        guard var t = todayPlan else { return false }
        func findIndex(_ name: String) -> Int? {
            t.plan.exercises.firstIndex { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == name.trimmingCharacters(in: .whitespaces).lowercased() }
        }
        switch opt.kind {
        case "add":
            guard let ex = opt.exercise, !ex.name.isEmpty else { return false }
            t.plan.exercises.append(ex)
            t.log.append(Array(repeating: SetLog(), count: ex.sets > 0 ? ex.sets : 3))
        case "extraSet":
            guard let i = findIndex(opt.target) else { return false }
            t.plan.exercises[i].sets = max(t.plan.exercises[i].sets, t.log[i].count) + 1
            t.log[i].append(SetLog())
        case "replace":
            guard let ex = opt.exercise, !ex.name.isEmpty, let i = findIndex(opt.target) else { return false }
            t.plan.exercises[i] = ex
            let kept = t.log[i].filter { $0.isLogged }
            let n = max(ex.sets > 0 ? ex.sets : 3, kept.count)
            t.log[i] = kept + Array(repeating: SetLog(), count: n - kept.count)
        default:
            return false
        }
        t.plan.estTimeMin += (opt.kind == "extraSet" ? 3 : 6)
        LocalStore.shared.logEvent(type: "plan_intensified", data: ["kind": .string(opt.kind), "target": .string(opt.target)])
        persistToday(t)
        return true
    }

    // MARK: - Rest timer

    func startRest(seconds: Double, exName: String, startedAt: Date = Date(), fromWatch: Bool = false) {
        rest = RestTimer(endsAt: startedAt.addingTimeInterval(seconds), total: seconds, exName: exName, fromWatch: fromWatch)
        WatchSync.shared.publish()
    }

    func extendRest(seconds: Int) {
        guard var r = rest else { return }
        r.endsAt = r.endsAt.addingTimeInterval(Double(seconds))
        r.total += Double(seconds)
        rest = r
        WatchSync.shared.publish()
    }

    func stopRest() {
        guard rest != nil else { return }
        rest = nil
        WatchSync.shared.publish()
    }

    // MARK: - Finish / cancel

    func finishSession() async {
        guard var t = todayPlan else { return }
        rest = nil
        let durationMin: Int? = {
            guard t.startedAt > 0 else { return nil }
            let mins = Int(((Date().timeIntervalSince1970 * 1000 - t.startedAt) / 60000).rounded())
            return min(mins, 240)
        }()
        t.finished = true
        t.fin = fin
        if let d = durationMin, d >= 10 { t.durationMin = d }
        t.log = t.log.map { ex in ex.map { s in
            var s = s
            if !s.weight.isEmpty || !s.reps.isEmpty || !s.time.isEmpty || !s.dist.isEmpty { s.done = true }
            return s
        } }

        let prior = history.filter { $0.id != t.id }
        let prs = Stats.detectPRs(t, prior)
        if !prs.isEmpty { t.prs = prs }

        history = prior + [t]
        LocalStore.shared.upsert(session: t)
        persistToday(t)
        LocalStore.shared.logEvent(type: "session_finished", data: [
            "date": .string(t.date), "sessionType": .string(t.plan.sessionType),
            "rpe": .number(Double(fin.rpe)), "prs": .number(Double(prs.count)),
        ])
        screen = .home
        Task { await runSync() }

        // Background: coach debrief on the finished session (unless switched off)
        if Prefs.isOn("debrief"), let text = try? await Gemini.generateDebrief(t, prior) {
            // the session may have been edited (or deleted) while the AI
            // was writing — attach the debrief to the latest copy only
            guard var latest = LocalStore.shared.backup.sessions.first(where: { $0.id == t.id }) else { return }
            latest.debrief = text
            LocalStore.shared.upsert(session: latest)
            if todayPlan?.id == latest.id { persistToday(latest) }
            if let i = history.firstIndex(where: { $0.id == latest.id }) { history[i] = latest }
            Task { await runSync() }
        }
    }

    func cancelSession() {
        LocalStore.shared.logEvent(type: "session_cancelled", data: [:])
        rest = nil
        persistToday(nil)
        screen = .home
    }

    // MARK: - Quick cardio (bypasses check-in and the AI entirely)

    /// `date` backdates the log (forgot to log yesterday's run); nil = today.
    func logQuickCardio(kind: String, time: String, dist: String, rpe: Int, date: String? = nil) async {
        let day = date ?? Helpers.todayStr()
        let meta: (sessionType: String, name: String) = {
            switch kind {
            case "run": return ("Run", "Running")
            case "cycle": return ("Cycle", "Cycling")
            case "walk": return ("Walk", "Brisk walk")
            case "hike": return ("Hike", "Hike")
            default: return ("", "")
            }
        }()
        guard !meta.sessionType.isEmpty else { return }
        let durationMin = Int(time)
        var plan = Plan(
            sessionType: meta.sessionType,
            title: !dist.isEmpty ? "\(dist)km \(meta.sessionType.lowercased())" : meta.sessionType,
            reasoning: "Logged directly from Home — not part of an AI-generated plan.",
            exercises: [Plan.Exercise(name: meta.name, sets: 1, rpe: rpe > 0 ? String(rpe) : "")],
            estTimeMin: durationMin ?? 0
        )
        plan.recoveryScore = nil
        let t = Session(
            id: "\(day)#\(Int(Date().timeIntervalSince1970 * 1000))",
            date: day, startedAt: Date().timeIntervalSince1970 * 1000,
            checkin: nil, plan: plan, log: [[SetLog(done: true, time: time, dist: dist)]],
            finished: true, fin: FinishInfo(rpe: rpe > 0 ? rpe : 6),
            durationMin: durationMin
        )
        // may be backdated — keep history in date order
        history = (history + [t]).sorted { ($0.date + $0.id) < ($1.date + $1.id) }
        LocalStore.shared.upsert(session: t)
        LocalStore.shared.logEvent(type: "quick_cardio_logged", data: ["kind": .string(kind), "date": .string(day)])
        Task { await runSync() }
    }

    // MARK: - Backup export / import (Settings → Your data)

    /// exportAll() in src/db/db.js: the account as one JSON file.
    func exportBackupFile() async throws -> URL {
        var b = LocalStore.shared.backup
        b.events = try await Cloud.shared.allEvents()
        b.workouts = Workouts.rawAll()
        b.prefs = Prefs.raw
        b.sessions.sort { ($0.date + $0.id) < ($1.date + $1.id) }
        b.health.sort { $0.date < $1.date }
        b.version = 4
        guard case .object(var o) = try JSONValue.encoding(b) else { throw CocoaError(.coderInvalidValue) }
        o["exportedAt"] = .string(ISO8601DateFormatter.withMillis.string(from: Date()))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-backup-\(Helpers.todayStr()).json")
        try JSONEncoder().encode(JSONValue.object(o)).write(to: url, options: .atomic)
        LocalStore.shared.logEvent(type: "data_exported", data: ["sessions": .number(Double(b.sessions.count))])
        return url
    }

    /// The spreadsheet-friendly export: one row per logged set.
    func exportCsvFile() throws -> URL {
        func esc(_ v: String) -> String { v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\"" : v }
        var rows = [["date", "session_type", "exercise", "set", "weight_kg", "reps", "effort", "session_rpe", "pain", "duration_min"]]
        for s in history {
            for (i, ex) in s.plan.exercises.enumerated() {
                for (si, set) in (s.log[safe: i] ?? []).enumerated() where set.done || !set.weight.isEmpty || !set.reps.isEmpty {
                    rows.append([s.date, s.plan.sessionType, ex.name, "\(si + 1)", set.weight, set.reps, set.effort,
                                 s.fin.map { "\($0.rpe)" } ?? "", s.fin?.pain ?? "", s.durationMin.map(String.init) ?? ""])
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-sessions-\(Helpers.todayStr()).csv")
        try rows.map { $0.map(esc).joined(separator: ",") }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        LocalStore.shared.logEvent(type: "data_exported_csv", data: ["rows": .number(Double(rows.count - 1))])
        return url
    }

    /// importAll() in src/db/db.js: the backup becomes the account's data
    /// (sessions/health replaced, events + deletions added, AI settings
    /// only if the backup's are newer), then GitHub is backed up.
    func importBackup(_ data: Data) async throws -> String {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data), case .array? = o["sessions"] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Not a valid COACH backup file."])
        }
        let b = GitHubSync.normalizeBackup(try JSONDecoder().decode(Backup.self, from: data))
        let skipped = try await Cloud.shared.replaceData(with: b)
        if b.aiSettings.updatedAt > LocalStore.shared.backup.aiSettings.updatedAt {
            Cloud.shared.putAISettings(b.aiSettings)
        }
        // saved workouts: add missing ones, newer copies win (replaceAll in src/db/db.js)
        for raw in b.workouts {
            guard case .object(let o) = raw, case .string(let id)? = o["id"], !id.isEmpty else { continue }
            let mine: Double = { if case .object(let m)? = Cloud.shared.stateValue("workout-\(id)"), case .number(let u)? = m["updatedAt"] { return u }; return -1 }()
            let theirs: Double = { if case .number(let u)? = o["updatedAt"] { return u }; return 0 }()
            if theirs > mine { Cloud.shared.setState("workout-\(id)", raw) }
        }
        if let p = b.prefs, Prefs.raw == nil { Cloud.shared.setState("prefs", p) }
        LocalStore.shared.logEvent(type: "data_imported", data: ["sessions": .number(Double(b.sessions.count)), "events": .number(Double(b.events.count))])
        Task { await runSync(replaceRemote: true) } // restored backup becomes the GitHub copy too
        return "Restored \(b.sessions.count) sessions from backup\(skipped > 0 ? " (\(skipped) kept: newer or deleted here)" : "")."
    }

    // MARK: - Past workout (typed in after the fact)

    /// Mirrors addPastSession() in src/App.jsx: a finished session dated
    /// the day it happened — no check-in, no AI — with PRs vs. what was
    /// logged before that day.
    func addPastSession(date: String, sessionType: String, exercises: [Plan.Exercise], log: [[SetLog]], durationMin: Int?, rpe: Int, feedback: String) {
        var plan = Plan(
            sessionType: sessionType, title: sessionType,
            reasoning: "Added afterwards from the Log — not part of an AI-generated plan.",
            exercises: exercises, estTimeMin: durationMin ?? 0
        )
        plan.recoveryScore = nil
        var t = Session(
            id: "\(date)#\(Int64(Date().timeIntervalSince1970 * 1000))", date: date, startedAt: 0,
            checkin: nil, plan: plan, log: log, finished: true,
            fin: FinishInfo(rpe: rpe, pain: "", feedback: feedback),
            durationMin: durationMin, backfilled: true
        )
        let prs = Stats.detectPRs(t, history.filter { $0.date < date })
        if !prs.isEmpty { t.prs = prs }
        history = (history + [t]).sorted { ($0.date + $0.id) < ($1.date + $1.id) }
        LocalStore.shared.upsert(session: t)
        LocalStore.shared.logEvent(type: "past_session_added", data: [
            "date": .string(date), "sessionType": .string(sessionType),
            "exercises": .number(Double(exercises.count)),
            "setsDone": .number(Double(log.flatMap { $0 }.count)), "prs": .number(Double(prs.count)),
        ])
        screen = .history
        Task { await runSync() }
    }

    // MARK: - History management

    func clearHistory() async {
        history = []
        persistToday(nil)
        LocalStore.shared.clearSessions()
        LocalStore.shared.logEvent(type: "history_cleared", data: [:])
        // back up now so the GitHub copy matches right away
        await runSync(replaceRemote: true)
    }

    func deleteSession(_ s: Session) async {
        LocalStore.shared.hardDelete(sessionId: s.id)
        history.removeAll { $0.id == s.id }
        if todayPlan?.id == s.id { persistToday(nil) }
        LocalStore.shared.logEvent(type: "session_deleted", data: ["id": .string(s.id)])
        await runSync()
    }

    func updateSession(_ s: Session) async {
        LocalStore.shared.upsert(session: s)
        if let i = history.firstIndex(where: { $0.id == s.id }) { history[i] = s }
        if todayPlan?.id == s.id { persistToday(s) }
        LocalStore.shared.logEvent(type: "session_edited", data: ["id": .string(s.id)])
        await runSync()
    }

    func reloadFromDb() {
        loadActive()
    }
}
