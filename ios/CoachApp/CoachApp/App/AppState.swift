import Foundation

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
    case records
    case progress
    case settings
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
@Observable
final class AppState {
    var screen: Screen = .loading
    var history: [Session] = []
    var todayPlan: Session? = nil
    var chatOpen = false
    var detailSession: Session? = nil
    var error = ""
    var statusMsg = ""
    var syncInfo: SyncInfo? = nil
    var weeklyReview: WeeklyReviewCache? = nil
    var monthlyReport: MonthlyReportCache? = nil

    var ci = Checkin()
    var fin = FinishInfo()

    var muscleGap: (group: String, lastDaysAgo: Int)? { Stats.biggestMuscleGap(history) }

    private var lastSyncAt: Date = .distantPast
    private var syncTask: Task<Void, Never>?

    init() {
        screen = Account.needsLogin() ? .login : .home
        if screen == .home {
            Task { await boot() }
        }
    }

    // MARK: - Boot

    func boot() async {
        loadActive()
        todayPlan = Defaults.codable(Session.self, "today")
        LocalStore.shared.logEvent(type: "app_open", data: ["sessions": .number(Double(history.count))])
        Task { await runSync() }
        Task { await maybeWeeklyReview() }
        Task { await maybeMonthlyReport() }
        screen = Keychain.apiKey.isEmpty ? .settings : .home
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
        Defaults.setCodable(t, for: "today")
    }

    // MARK: - Sync

    @discardableResult
    func runSync(replaceRemote: Bool = false) async -> GitHubSync.Result? {
        lastSyncAt = Date()
        syncInfo = SyncInfo(state: "syncing")
        do {
            let r = try await GitHubSync.syncNow(replaceRemote: replaceRemote)
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
        Task { await runSync() }
    }

    // MARK: - Check-in defaults

    func buildDefaultCheckin() -> Checkin {
        var c = Checkin()
        c.health = todaysHealth()
        return c
    }

    /// Today's health row (from the Watch-shortcut inbox, drained on
    /// sync) formatted for the check-in — mirrors todaysHealth() in
    /// src/utils/healthIngest.js's common case (the URL-hash /
    /// clipboard paths are web-only).
    private func todaysHealth() -> String? {
        guard let row = LocalStore.shared.backup.health.first(where: { $0.date == Helpers.todayStr() }) else { return nil }
        return row.raw
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

        do {
            let plan = try await Gemini.generateWorkoutPlan(checkin: checkin, history: history) { [weak self] msg in
                Task { @MainActor in self?.statusMsg = msg }
            }
            LocalStore.shared.logEvent(type: "plan_generated", data: [
                "sessionType": .string(plan.sessionType), "title": .string(plan.title),
                "estTimeMin": .number(Double(plan.estTimeMin)),
            ])
            let log = plan.exercises.map { ex in Array(repeating: SetLog(), count: max(ex.sets, 1)) }
            let t = Session(
                id: "\(Helpers.todayStr())#\(Int(Date().timeIntervalSince1970 * 1000))",
                date: Helpers.todayStr(), startedAt: Date().timeIntervalSince1970 * 1000,
                checkin: checkin, plan: plan, log: log, finished: false
            )
            persistToday(t)
            screen = .workout
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
        guard Calendar.current.component(.weekday, from: Date()) == 1 else { return } // Sundays only (1 = Sunday)
        let cur = Defaults.codable(WeeklyReviewCache.self, "weekly-review")
        let thisMonday = Stats.mondayOf(Helpers.todayStr())
        guard cur?.week != thisMonday else { return }
        guard let summary = Stats.lastWeekSummary(history), !Keychain.apiKey.isEmpty else { return }
        guard let text = try? await Gemini.generateWeeklyReview(summary) else { return }
        let review = WeeklyReviewCache(week: thisMonday, at: Date().timeIntervalSince1970 * 1000, text: text, count: summary.count, progressions: summary.progressions)
        Defaults.setCodable(review, for: "weekly-review")
        weeklyReview = review
    }

    private func maybeMonthlyReport() async {
        let now = Date()
        let cal = Calendar.current
        guard cal.component(.day, from: now) <= 7 else { return } // first week of the month only
        guard let prevMonthDate = cal.date(byAdding: .month, value: -1, to: now) else { return }
        let ym = "\(cal.component(.year, from: prevMonthDate))-\(String(format: "%02d", cal.component(.month, from: prevMonthDate)))"
        let cur = Defaults.codable(MonthlyReportCache.self, "monthly-report")
        guard cur?.month != ym else { return }
        guard !Keychain.apiKey.isEmpty else { return }
        guard let sum = Stats.monthSummary(history, LocalStore.shared.backup.health, ym: ym) else { return }
        guard let text = try? await Gemini.generateMonthlyReport(sum) else { return }
        let report = MonthlyReportCache(month: ym, at: Date().timeIntervalSince1970 * 1000, text: text, sum: sum)
        Defaults.setCodable(report, for: "monthly-report")
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
        if let weight { s.weight = weight }
        if let reps { s.reps = reps }
        if let time { s.time = time }
        if let dist { s.dist = dist }
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
            t.log.append(Array(repeating: SetLog(), count: max(ex.sets, 1)))
        case "extraSet":
            guard let i = findIndex(opt.target) else { return false }
            t.plan.exercises[i].sets = max(t.plan.exercises[i].sets, t.log[i].count) + 1
            t.log[i].append(SetLog())
        case "replace":
            guard let ex = opt.exercise, !ex.name.isEmpty, let i = findIndex(opt.target) else { return false }
            t.plan.exercises[i] = ex
            let kept = t.log[i].filter { $0.isLogged }
            let n = max(ex.sets, kept.count)
            t.log[i] = kept + Array(repeating: SetLog(), count: n - kept.count)
        default:
            return false
        }
        t.plan.estTimeMin += (opt.kind == "extraSet" ? 3 : 6)
        LocalStore.shared.logEvent(type: "plan_intensified", data: ["kind": .string(opt.kind), "target": .string(opt.target)])
        persistToday(t)
        return true
    }

    // MARK: - Finish / cancel

    func finishSession() async {
        guard var t = todayPlan else { return }
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

        // Background: coach debrief on the finished session
        if let text = try? await Gemini.generateDebrief(t, prior) {
            var t2 = t
            t2.debrief = text
            LocalStore.shared.upsert(session: t2)
            if todayPlan?.id == t2.id { persistToday(t2) }
            if let i = history.firstIndex(where: { $0.id == t2.id }) { history[i] = t2 }
            Task { await runSync() }
        }
    }

    func cancelSession() {
        LocalStore.shared.logEvent(type: "session_cancelled", data: [:])
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

    // MARK: - History management

    func clearHistory() async {
        history = []
        persistToday(nil)
        LocalStore.shared.clearSessions()
        LocalStore.shared.logEvent(type: "history_cleared", data: [:])
        // overwrite the cloud too — a merge would resurrect the deleted data
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
