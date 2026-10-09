import SwiftUI

/// Ports src/screens/Home.jsx — the Today tab: readiness, this week's
/// numbers, the start button, quick launchers, today's plan and the
/// coach's notes.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var quickCardioKind: String? = nil
    /// the readiness notice was dismissed on this day (yyyy-MM-dd)
    /// Dismissing today's recovery notice is account state (`noticeDismissed`,
    /// shared with the web app), so every device hides it.
    private var noticeDismissed: String {
        _ = appState.stateTick
        if case .string(let d)? = Cloud.shared.stateValue("noticeDismissed") { return d }
        return ""
    }

    private var doneToday: Bool { appState.todayPlan?.finished == true }
    private var inProgress: Bool { appState.todayPlan != nil && appState.todayPlan?.finished == false }
    private var settings: AISettings { LocalStore.shared.backup.aiSettings }
    private var health: [HealthRow] { LocalStore.shared.backup.health }

    private var showReview: Bool {
        guard let r = appState.weeklyReview else { return false }
        return Date().timeIntervalSince1970 * 1000 - r.at < 7 * 86400 * 1000
    }
    private var showMonthly: Bool {
        guard let r = appState.monthlyReport else { return false }
        return Date().timeIntervalSince1970 * 1000 - r.at < 10 * 86400 * 1000
    }

    var body: some View {
        let target = Dashboard.weeklyTarget(settings)
        let week = Stats.weekStats(appState.history, target: target)
        let kcal = Calories.stats(appState.history, bodyKg: Calories.latestBodyWeightKg(health)).thisWeek
        let readiness = Dashboard.readiness(appState.history, health)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TabHeader(title: "Today")
                hero(readiness)
                HStack(spacing: 10) {
                    StatBlock(value: "\(week.thisWeek)", label: "This week")
                    StatBlock(value: "\(week.streak)", label: "Streak (wks)", color: Theme.amberText)
                    StatBlock(value: kcal >= 10000 ? "\(kcal / 1000)k" : "\(kcal)", label: "Active kcal")
                }
                startButton
                quickLaunch
                focus(target: target)
                if let r = readiness, noticeDismissed != Helpers.todayStr() { notice(r) }
                if showMonthly, let r = appState.monthlyReport { monthlyCard(r) }
                if showReview, let r = appState.weeklyReview { weeklyCard(r) }
                // sync status lives in Settings; Today only speaks up when it fails
                if let sync = appState.syncInfo, sync.state == "error" {
                    Text("Sync error — \(sync.message ?? "")").font(Theme.meta(12.5)).foregroundStyle(Theme.red)
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .coachScreen()
        .sheet(item: $quickCardioKind) { kind in
            QuickCardioSheet(kind: kind) { kind, time, dist, rpe, date in
                Task { await appState.logQuickCardio(kind: kind, time: time, dist: dist, rpe: rpe, date: date) }
            }
        }
        .onAppear { appState.maybeSyncOnForeground() }
    }

    // MARK: Sections

    private func hero(_ r: Dashboard.Readiness?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .capsLabel()
            HStack(alignment: .center, spacing: 10) {
                Text(heroTitle)
                    .font(Theme.head(36, weight: .bold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if doneToday {
                    StatusPill(text: "Done", color: Theme.green)
                } else if let r {
                    StatusPill(text: r.label, color: tone(r.tone))
                }
            }
        }
    }

    private var heroTitle: String {
        let name = appState.firstName
        if doneToday { return name.map { "Nice work, \($0)." } ?? "Session done." }
        if inProgress { return "\(appState.todayPlan?.plan.sessionType ?? "Session") in progress" }
        return name.map { "Ready, \($0)?" } ?? "Ready?"
    }

    private func tone(_ t: Dashboard.Tone) -> Color {
        switch t {
        case .good: return Theme.green
        case .ok: return Theme.amberText
        case .low: return Theme.red
        }
    }

    private var startButton: some View {
        Button {
            if inProgress {
                appState.screen = .workout
            } else {
                Task {
                    appState.ci = await appState.prepareCheckin()
                    appState.error = ""
                    appState.screen = .checkIn
                }
            }
        } label: {
            Text(inProgress ? "Resume \(appState.todayPlan?.plan.sessionType ?? "")" : (doneToday ? "Plan another session" : "Start workout"))
        }
        .buttonStyle(BigButtonStyle(icon: "play.fill"))
    }

    private var quickLaunch: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHead(title: "Quick launch", trailing: "Manual activity") { appState.screen = .addPast }
            HStack(spacing: 8) {
                if !inProgress {
                    LaunchTile(icon: "timer", label: "Quick") {
                        Task {
                            let checkin = await appState.prepareCheckin()
                            appState.ci = checkin
                            LocalStore.shared.logEvent(type: "quick_start")
                            var c = checkin
                            c.notes = "Quick start — assumed a normal day."
                            await appState.generateWorkout(c)
                        }
                    }
                }
                ForEach([("run", "figure.run", "Run"), ("cycle", "bicycle", "Ride"), ("walk", "figure.walk", "Walk"), ("hike", "figure.hiking", "Hike")], id: \.0) { kind, icon, label in
                    LaunchTile(icon: icon, label: label, tint: Theme.green) { quickCardioKind = kind }
                }
            }
        }
    }

    // MARK: Today's focus

    @ViewBuilder
    private func focus(target: Int) -> some View {
        let t = appState.todayPlan
        VStack(alignment: .leading, spacing: 10) {
            // the session's status while there is one; otherwise the way to your saved workouts
            if let t {
                SectionHead(title: "Today's focus", trailing: t.finished ? "Completed" : "Scheduled",
                            trailingColor: t.finished ? Theme.green : Theme.amberText)
            } else {
                SectionHead(title: "Today's focus", trailing: "My workouts") { appState.openWorkouts(from: .home) }
            }
            if let t { planCard(t) }
            else if let w = scheduled.sessions.first { savedCard(w, more: scheduled.sessions.count - 1, addOns: scheduled.addOns) }
            else { emptyFocus }
        }
    }

    private func planCard(_ t: Session) -> some View {
        let p = t.plan
        let total = t.log.reduce(0) { $0 + $1.count }
        let done = t.log.reduce(0) { $0 + $1.filter(\.done).count }
        let load = Dashboard.projectedLoad(p, appState.history)
        let meta = [p.estTimeMin > 0 ? "\(p.estTimeMin) min" : nil,
                    Dashboard.averageRPE(p).map { "RPE \(Helpers.fmtKg($0))" },
                    "\(p.exercises.count) exercises"].compactMap { $0 }.joined(separator: " • ")
        return CoachCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title.isEmpty ? p.sessionType : p.title)
                        .font(Theme.head(26, weight: .bold)).textCase(.uppercase).tracking(0.5)
                        .foregroundStyle(Theme.text).lineLimit(2)
                    Text(meta).capsLabel(Theme.amberText, size: 13)
                }
                Spacer()
                IconWell(icon: "arrow.up.left.and.arrow.down.right")
            }
            ProgressLine(fraction: total > 0 ? Double(done) / Double(total) : 0, color: t.finished ? Theme.green : Theme.amber)
                .padding(.vertical, 6)
            HStack {
                Text(load > 0 ? "Target load: \(Self.kgShort(load)) kg volume" : "\(done)/\(total) sets done")
                    .font(Theme.meta(13)).foregroundStyle(Theme.muted)
                Spacer()
                Button { appState.screen = .workout } label: {
                    HStack(spacing: 6) {
                        Text(t.finished ? "View" : (done > 0 ? "Resume" : "Start"))
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    }
                    .font(Theme.head(15, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.bgHigh)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                .buttonStyle(.plain)
                .disabled(t.finished)
                .opacity(t.finished ? 0.5 : 1)
            }
        }
    }

    private var scheduled: (sessions: [SavedWorkout], addOns: [SavedWorkout]) {
        _ = appState.stateTick
        return Workouts.scheduledFor()
    }

    /// No plan yet, but the library has a workout on today's weekday.
    private func savedCard(_ w: SavedWorkout, more: Int, addOns: [SavedWorkout]) -> some View {
        CoachCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled today" + (w.source == "trainer" ? " · \(w.trainer.isEmpty ? "trainer" : w.trainer)'s workout" : ""))
                        .capsLabel(Theme.amberText, size: 12)
                    Text(w.name).font(Theme.head(26, weight: .bold)).textCase(.uppercase).tracking(0.5).foregroundStyle(Theme.text).lineLimit(2)
                    Text("\(w.exercises.count) exercises · \(w.adapt ? "coach adapts it to today" : "kept as written")"
                         + (addOns.isEmpty ? "" : " · + " + addOns.map(\.name).joined(separator: ", ")))
                        .font(Theme.meta(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                IconWell(icon: "list.bullet.clipboard")
            }
            ExerciseSummary(exercises: w.exercises, max: 4).padding(.vertical, 4)
            HStack {
                Button(more > 0 ? "\(more) more scheduled today" : "All my workouts") { appState.openWorkouts(from: .home) }
                    .font(Theme.body(13.5)).foregroundStyle(Theme.amberText)
                Spacer()
                Button {
                    Task { await appState.startSavedWorkout(w.id) }
                } label: {
                    HStack(spacing: 6) {
                        Text("Start")
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    }
                    .font(Theme.head(15, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.bgHigh)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyFocus: some View {
        CoachCard {
            Text("No plan yet").font(Theme.head(24, weight: .bold)).textCase(.uppercase).tracking(0.5)
            Text("A one-minute check-in and the coach builds today's session around your recovery.")
                .font(Theme.body(14)).foregroundStyle(Theme.muted)
        }
    }

    /// 12400 → "12.4k"
    static func kgShort(_ kg: Int) -> String {
        kg >= 1000 ? String(format: "%.1fk", Double(kg) / 1000).replacingOccurrences(of: ".0k", with: "k") : "\(kg)"
    }

    // MARK: Notices + reviews

    private func notice(_ r: Dashboard.Readiness) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconWell(icon: r.tone == .low ? "exclamationmark.triangle" : "checkmark.shield", tint: tone(r.tone), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.tone == .low ? "Go easier today" : r.tone == .good ? "Recovery looks good" : "Normal recovery")
                    .capsLabel(tone(r.tone), size: 12)
                Text(r.note).font(Theme.body(14)).foregroundStyle(Theme.textBody).lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { Cloud.shared.setState("noticeDismissed", .string(Helpers.todayStr())); appState.stateTick += 1 } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func monthlyCard(_ r: MonthlyReportCache) -> some View {
        CoachCard {
            SectionHead(title: "Monthly report", trailing: "\(r.sum.count) sessions")
            ExpandableText(text: r.text)
        }
    }

    private func weeklyCard(_ r: WeeklyReviewCache) -> some View {
        CoachCard {
            SectionHead(title: "Weekly review", trailing: "\(r.count) sessions")
            ExpandableText(text: r.text)
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    HomeView().environment(AppState())
}
