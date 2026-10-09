import SwiftUI

/// Ports src/screens/Records.jsx — the honor roll (milestones unlocked),
/// lifetime stats, the milestone grid with progress, personal records
/// (tap one for its est. 1RM trend) and the next benchmark in reach.
struct RecordsView: View {
    @Environment(AppState.self) private var appState
    @State private var openEx: String?
    @State private var showAll = false
    @State private var share: ShareItems?

    var body: some View {
        let history = appState.history
        let records = Stats.prRecords(history).filter { $0.weight != nil }
            .sorted { ($0.weight?.date ?? "") > ($1.weight?.date ?? "") }
        let series = Stats.exerciseSeries(history)
        let totalVolume = history.reduce(0) { $0 + Stats.sessionVolume($1) }
        let streak = Stats.weekStats(history, target: Dashboard.weeklyTarget(LocalStore.shared.backup.aiSettings)).streak
        let milestones = Dashboard.milestones(history)
        let earned = milestones.filter(\.earned).count

        return ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(title: "Records")

                honorRoll(earned: earned, records: records.count)

                HStack(spacing: 8) {
                    StatTile(label: "Sessions", value: "\(history.count)", sub: history.isEmpty ? nil : "Active", subColor: Theme.green)
                    StatTile(label: "Lifted",
                             value: totalVolume >= 10000 ? "\(Int((Double(totalVolume) / 1000).rounded()))" : String(format: "%.1f", Double(totalVolume) / 1000),
                             unit: "t", sub: "Lifetime")
                    StatTile(label: "Streak", value: "\(streak)", unit: "wks", sub: streak >= 2 ? "Hot" : nil, subColor: Theme.amberText)
                }

                HStack(spacing: 8) {
                    Button { share = ShareItems(items: [shareText(history)]) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button {
                        if let url = try? recordsCsv(history) { share = ShareItems(items: [url]) }
                    } label: { Label("Export CSV", systemImage: "tablecells") }
                }
                .buttonStyle(OutlineButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    SectionHead(title: "Key milestones", trailing: "\(earned) of \(milestones.count) complete", trailingColor: Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Dashboard.keyMilestones(history)) { m in milestoneTile(m) }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHead(title: "Personal records", trailing: records.count > 6 ? (showAll ? "Top 6" : "All PRs") : nil) { showAll.toggle() }
                    if records.isEmpty {
                        Text("Log weighted sets to see records.").font(Theme.body(14)).foregroundStyle(Theme.muted)
                    }
                    ForEach(showAll ? records : Array(records.prefix(6)), id: \.name) { r in
                        recordRow(r, points: series.first { $0.name == r.name }?.points ?? []).id("pr-\(r.name.lowercased())")
                    }
                }

                if let next = Dashboard.nextBenchmark(history) {
                    HStack(spacing: 12) {
                        IconWell(icon: "flame.fill", tint: Theme.amberText, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next benchmark in reach").font(Theme.body(15, weight: .medium))
                            Text("\(next.goal - next.value) more to unlock \(next.title.lowercased())")
                                .font(Theme.meta(13)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        // opened from search: open that lift's row and bring it into view
        .onAppear { showPick(proxy) }
        .onChange(of: appState.recordPick) { _, _ in showPick(proxy) }
        }
        .coachScreen()
        .sheet(item: $share) { RecordsShareSheet(items: $0.items) }
    }

    private func showPick(_ proxy: ScrollViewProxy) {
        guard let pick = appState.recordPick, Date().timeIntervalSince(pick.at) < 5 else { return }
        openEx = pick.name
        showAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo("pr-\(pick.name.lowercased())", anchor: .center) }
        }
    }

    // MARK: - Share / export (ports shareRecords / exportRecordsCsv in Records.jsx)

    private func shareText(_ history: [Session]) -> String {
        let records = Stats.prRecords(history).filter { $0.weight != nil }
            .sorted { ($0.e1rm?.v ?? $0.weight!.w) > ($1.e1rm?.v ?? $1.weight!.w) }
        let earned = Dashboard.milestones(history).filter(\.earned)
        var lines = ["My training records — \(history.count) sessions, \(records.count) PRs, \(earned.count) milestones"]
        lines += records.prefix(6).map { r in
            "• \(r.name): \(Helpers.fmtKg(r.weight!.w)) kg × \(r.weight!.reps.isEmpty ? "?" : r.weight!.reps)" + (r.e1rm.map { " (est. 1RM \(Helpers.fmtKg($0.v)) kg)" } ?? "")
        }
        if let last = earned.last { lines.append("Latest milestone: \(last.title)") }
        return lines.joined(separator: "\n")
    }

    private func recordsCsv(_ history: [Session]) throws -> URL {
        func esc(_ v: String) -> String { v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\"" : v }
        var rows = ["Exercise,Muscle group,Best weight (kg),Reps,Best set date,Est. 1RM (kg),Est. 1RM date,Sets logged"]
        for r in Stats.prRecords(history) {
            guard let w = r.weight else { continue }
            rows.append([r.name, Stats.muscleGroupOf(r.name), Helpers.fmtKg(w.w), w.reps, w.date,
                         r.e1rm.map { Helpers.fmtKg($0.v) } ?? "", r.e1rm?.date ?? "", "\(r.count)"].map(esc).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-records-\(Helpers.todayStr()).csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        LocalStore.shared.logEvent(type: "records_exported", data: ["records": .number(Double(rows.count - 1))])
        return url
    }

    private func honorRoll(earned: Int, records: Int) -> some View {
        CoachCard(stroke: Theme.amber.opacity(0.35)) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(text: "Honor roll", color: Theme.amberText, dot: false)
                    Text("\(earned) milestone\(earned == 1 ? "" : "s") unlocked")
                        .font(Theme.head(28, weight: .bold)).textCase(.uppercase).tracking(0.5)
                    Text("\(records) personal record\(records == 1 ? "" : "s") on the board").font(Theme.meta(13)).foregroundStyle(Theme.green)
                }
                Spacer()
                Image(systemName: "trophy.fill").font(.system(size: 30)).foregroundStyle(Theme.amberText)
                    .frame(width: 64, height: 64).background(Theme.amberBg).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
        }
    }

    private func milestoneTile(_ m: Dashboard.Milestone) -> some View {
        HStack(spacing: 10) {
            IconWell(icon: m.icon, tint: m.earned ? Theme.amberText : Theme.dim, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title).font(Theme.body(14, weight: .medium)).foregroundStyle(m.earned ? Theme.text : Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if m.earned {
                    Label("Unlocked", systemImage: "checkmark.circle.fill").font(Theme.meta(11.5)).foregroundStyle(Theme.green)
                } else {
                    ProgressLine(fraction: Double(m.value) / Double(m.goal), height: 4)
                    Text("\(m.value) / \(m.goal)").font(Theme.meta(11)).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(m.earned ? Theme.amber.opacity(0.35) : Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func recordRow(_ r: Stats.ExercisePR, points: [Stats.ExercisePoint]) -> some View {
        let isOpen = openEx?.lowercased() == r.name.lowercased()
        let isNew = (r.weight?.date ?? "") >= Helpers.daysAgoStr(6)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconWell(icon: isNew ? "star.fill" : "medal", tint: isNew ? Theme.amberText : Theme.muted, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(Theme.body(15, weight: .medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        if isNew { Text("New").capsLabel(Theme.amberText, size: 11) }
                        Text([Stats.muscleGroupOf(r.name), r.e1rm.map { "e1RM \(Helpers.fmtKg($0.v))kg" }].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.meta(12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Helpers.fmtKg(r.weight!.w)).font(Theme.head(22, weight: .bold)).foregroundStyle(Theme.amberText)
                    Text("kg × \(r.weight!.reps.isEmpty ? "?" : r.weight!.reps)").capsLabel(Theme.muted, size: 11)
                }
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0)).foregroundStyle(Theme.dim)
            }
            if isOpen {
                if points.count >= 2 {
                    LineChartView(points: points.map { ChartPoint(label: Self.shortDate($0.date), value: $0.e ?? $0.w) }, unit: "kg", height: 150)
                } else {
                    Text("One more session unlocks the trend.").font(Theme.meta(13)).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(12)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { openEx = isOpen ? nil : r.name } }
    }

    /// "2026-08-30" → "30/8", like the web's toLocaleDateString day/month.
    static func shortDate(_ iso: String) -> String {
        guard let d = Helpers.noonDate(iso) else { return iso }
        return d.formatted(.dateTime.day().month(.defaultDigits))
    }
}

/// `.stat-tile` — caps label, big number, optional caps note.
struct StatTile: View {
    let label: String
    let value: String
    var unit = ""
    var sub: String? = nil
    var subColor: Color = Theme.muted
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).capsLabel(Theme.muted, size: 11).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.head(30, weight: .bold))
                if !unit.isEmpty { Text(unit).capsLabel(Theme.muted, size: 12) }
            }
            if let sub { Text(sub).capsLabel(subColor, size: 10.5) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

private struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The iOS share sheet (Messages, AirDrop, Save to Files…).
private struct RecordsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
