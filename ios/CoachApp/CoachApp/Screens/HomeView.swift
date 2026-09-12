import SwiftUI

/// Ports src/screens/Home.jsx — the daily landing screen.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var quickCardioKind: String? = nil

    private var name: String? {
        Account.current()?.name.split(separator: " ").first.map(String.init)
    }

    private var last: Session? { appState.history.last }
    private var doneToday: Bool { appState.todayPlan?.finished == true }
    private var inProgress: Bool { appState.todayPlan != nil && appState.todayPlan?.finished == false }
    private var weekStats: (thisWeek: Int, streak: Int) { Stats.weekStats(appState.history) }
    private var deload: Stats.DeloadSignal? { Stats.deloadSignal(appState.history) }

    private var showReview: Bool {
        guard let r = appState.weeklyReview else { return false }
        return Date().timeIntervalSince1970 * 1000 - r.at < 7 * 86400 * 1000
    }
    private var showMonthly: Bool {
        guard let r = appState.monthlyReport else { return false }
        return Date().timeIntervalSince1970 * 1000 - r.at < 10 * 86400 * 1000
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                hero
                if !appState.history.isEmpty { statRow }
                actionButtons
                if let deload { deloadCard(deload) }
                if let last { lastSessionCard(last) }
                if showMonthly, let r = appState.monthlyReport { monthlyCard(r) }
                if showReview, let r = appState.weeklyReview { weeklyCard(r) }
                if let sync = appState.syncInfo { syncFootnote(sync) }
            }
            .padding(16)
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

    private var header: some View {
        HStack {
            Text("COACH")
                .font(Theme.head(18, weight: .bold))
                .textCase(.uppercase)
                .tracking(4)
                .foregroundStyle(Theme.amber)
            Spacer()
            HStack(spacing: 16) {
                Button { appState.screen = .settings } label: {
                    Image(systemName: "gearshape").foregroundStyle(Theme.dim)
                }
                Button("Stats") { appState.screen = .progress }
                Button("🏆") { appState.screen = .records }
                Button("Log") { appState.screen = .history }
            }
            .font(Theme.head(15, weight: .semibold))
            .foregroundStyle(Theme.dim)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(Theme.mono(12))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.muted)

            Text(heroTitle)
                .font(Theme.head(38, weight: .bold))
                .foregroundStyle(Theme.text)

            Text(heroSubtitle)
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 10)
    }

    private var heroTitle: String {
        if doneToday { return name.map { "Nice work, \($0)." } ?? "Session done." }
        if inProgress { return "Session in progress" }
        return name.map { "Ready when you are, \($0)." } ?? "Ready when you are."
    }

    private var heroSubtitle: String {
        if doneToday, let t = appState.todayPlan { return "\(t.plan.sessionType) logged. Recovery feeds tomorrow's plan." }
        if inProgress, let t = appState.todayPlan { return "\(t.plan.sessionType) — pick up where you left off." }
        return "60-second check-in. The plan, the weights, the timing — handled."
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            statTile("This week", "\(weekStats.thisWeek)", "sessions")
            statTile("Week streak (≥3)", "\(weekStats.streak)", "wks")
        }
    }

    private func statTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.head(12, weight: .semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.muted)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(Theme.body(26, weight: .semibold)).foregroundStyle(Theme.text)
                Text(unit).font(Theme.body(13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                if inProgress {
                    appState.screen = .workout
                } else {
                    Task {
                        appState.ci = appState.buildDefaultCheckin()
                        appState.error = ""
                        appState.screen = .checkIn
                    }
                }
            } label: {
                Text(inProgress ? "Resume \(appState.todayPlan?.plan.sessionType ?? "")" : (doneToday ? "Plan another session" : "Start check-in"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle())

            HStack(spacing: 10) {
                if !inProgress {
                    Button("⚡ Quick start") {
                        Task {
                            let checkin = appState.buildDefaultCheckin()
                            appState.ci = checkin
                            LocalStore.shared.logEvent(type: "quick_start")
                            var c = checkin
                            c.notes = "Quick start — assumed a normal day."
                            await appState.generateWorkout(c)
                        }
                    }
                    Text("·").foregroundStyle(Theme.borderDim)
                }
                Button("🗨 Ask coach") { appState.chatOpen = true }
            }
            .font(Theme.mono(13.5))
            .foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                ForEach([("run", "🏃 Run"), ("cycle", "🚴 Ride"), ("walk", "🚶 Walk"), ("hike", "🥾 Hike")], id: \.0) { kind, label in
                    if kind != "run" { Text("·").foregroundStyle(Theme.borderDim) }
                    Button(label) { quickCardioKind = kind }
                }
            }
            .font(Theme.mono(13.5))
            .foregroundStyle(Theme.muted)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func deloadCard(_ d: Stats.DeloadSignal) -> some View {
        card {
            Text("⚠ Deload suggested").font(Theme.head(13, weight: .semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.amber)
            Text(d.reason).font(Theme.body(14.5)).foregroundStyle(Theme.textBody)
            Text("The coach factors this into every plan it builds this week.")
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber))
    }

    private func lastSessionCard(_ s: Session) -> some View {
        card {
            Text("Last session").font(Theme.head(13, weight: .semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.muted)
            HStack {
                Text(Helpers.fmtDate(s.date)).font(Theme.mono(14))
                Spacer()
                Text(s.plan.sessionType).font(Theme.mono(14)).foregroundStyle(Theme.amber)
            }
            if let fin = s.fin {
                Text("Session RPE \(fin.rpe)/10\(fin.pain.isEmpty ? "" : " · pain: \(fin.pain)")")
                    .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            }
            if let debrief = s.debrief, !debrief.isEmpty {
                Text("🗨 \(debrief)").font(Theme.body(14)).foregroundStyle(Theme.textBody).padding(.top, 4)
            }
        }
    }

    private func monthlyCard(_ r: MonthlyReportCache) -> some View {
        card {
            Text("📆 Monthly report").font(Theme.head(13, weight: .semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.amber)
            Text("\(r.sum.count) sessions · \(r.sum.volume)kg lifted\(r.sum.progressions != "none" ? " · up: \(r.sum.progressions)" : "")")
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            Text(r.text).font(Theme.body(14.5)).foregroundStyle(Theme.textBody).padding(.top, 4)
        }
    }

    private func weeklyCard(_ r: WeeklyReviewCache) -> some View {
        card {
            Text("Weekly review").font(Theme.head(13, weight: .semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.muted)
            Text("\(r.count) sessions\(r.progressions != "none" ? " · up: \(r.progressions)" : "")")
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            Text(r.text).font(Theme.body(14.5)).foregroundStyle(Theme.textBody).padding(.top, 4)
        }
    }

    private func syncFootnote(_ sync: SyncInfo) -> some View {
        Group {
            switch sync.state {
            case "syncing": Text("☁ syncing…")
            case "ok": Text("☁ synced \((sync.at ?? Date()).formatted(date: .omitted, time: .shortened)) · \(sync.sessions ?? 0) sessions in cloud")
            default: Text("☁ sync error — \(sync.message ?? "")")
            }
        }
        .font(Theme.mono(12))
        .foregroundStyle(Theme.dim)
        .padding(.top, 4)
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    HomeView().environment(AppState())
}
