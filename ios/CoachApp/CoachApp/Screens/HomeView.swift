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
                // sync status lives in Settings; Home only speaks up when it fails
                if let sync = appState.syncInfo, sync.state == "error" { syncFootnote(sync) }
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
        Text("COACH")
            .font(Theme.head(18, weight: .bold))
            .tracking(4)
            .foregroundStyle(Theme.amber)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
            Text(heroTitle)
                .font(Theme.head(36, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.top, 6)
    }

    private var heroTitle: String {
        if doneToday { return name.map { "Nice work, \($0)." } ?? "Session done." }
        if inProgress { return "\(appState.todayPlan?.plan.sessionType ?? "Session") in progress" }
        return name.map { "Ready, \($0)?" } ?? "Ready?"
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            statTile("This week", "\(weekStats.thisWeek)", "sessions")
            statTile("Streak", "\(weekStats.streak)", "wks")
        }
    }

    private func statTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.body(13, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(Theme.head(30, weight: .bold)).foregroundStyle(Theme.text)
                Text(unit).font(Theme.body(13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
                        appState.ci = await appState.prepareCheckin()
                        appState.error = ""
                        appState.screen = .checkIn
                    }
                }
            } label: {
                Text(inProgress ? "Resume \(appState.todayPlan?.plan.sessionType ?? "")" : (doneToday ? "Plan another session" : "Start check-in"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle())

            // one row of shortcuts: skip the check-in, or log cardio directly
            HStack(spacing: 8) {
                if !inProgress {
                    shortcut("bolt.fill", "Quick start", tint: Theme.amber) {
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
                    shortcut(icon, label) { quickCardioKind = kind }
                }
            }
        }
    }

    private func shortcut(_ icon: String, _ label: String, tint: Color = Theme.teal, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(tint)
                    .frame(height: 22)
                Text(label).font(Theme.body(11.5, weight: .medium)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            Label("Deload suggested", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.amber)
            Text(d.reason).font(Theme.body(14.5)).foregroundStyle(Theme.textBody)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber))
    }

    private func lastSessionCard(_ s: Session) -> some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text(s.plan.sessionType).font(Theme.head(20, weight: .bold))
                Text(Helpers.fmtDate(s.date)).font(Theme.meta(13)).foregroundStyle(Theme.muted)
                Spacer()
                if let fin = s.fin {
                    Text("RPE \(fin.rpe)").font(Theme.meta(13, weight: .medium)).foregroundStyle(Theme.amber)
                }
            }
            if let debrief = s.debrief, !debrief.isEmpty {
                Text(debrief).font(Theme.body(14)).foregroundStyle(Theme.muted).lineLimit(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.detailSession = s
            appState.screen = .historyDetail
        }
    }

    private func monthlyCard(_ r: MonthlyReportCache) -> some View {
        card {
            CardLabel(text: "Monthly report", color: Theme.amber)
            Text("\(r.sum.count) sessions · \(r.sum.volume.formatted())kg lifted")
                .font(Theme.meta(13)).foregroundStyle(Theme.muted)
            ExpandableText(text: r.text)
        }
    }

    private func weeklyCard(_ r: WeeklyReviewCache) -> some View {
        card {
            CardLabel(text: "Weekly review")
            ExpandableText(text: r.text)
        }
    }

    private func syncFootnote(_ sync: SyncInfo) -> some View {
        Group {
            switch sync.state {
            case "syncing": Text("Syncing…")
            case "ok": Text("Synced")
            default: Text("Sync error — \(sync.message ?? "")")
            }
        }
        .font(Theme.meta(12.5))
        .foregroundStyle(Theme.red)
        .padding(.top, 4)
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    HomeView().environment(AppState())
}
