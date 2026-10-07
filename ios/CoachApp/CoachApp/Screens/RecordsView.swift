import SwiftUI

/// Ports src/screens/Records.jsx — lifetime stats, milestone badges and
/// personal records (tap one for its est. 1RM trend).
struct RecordsView: View {
    @Environment(AppState.self) private var appState
    @State private var openEx: String?

    private struct Ladder { var emoji: String; var unit: String; var value: Int; var steps: [Int] }

    var body: some View {
        let history = appState.history
        let records = Stats.prRecords(history).filter { $0.weight != nil }
        let series = Stats.exerciseSeries(history)
        let totalVolume = history.reduce(0) { $0 + Stats.sessionVolume($1) }
        let streak = Stats.weekStats(history).streak
        let heaviest = Int(records.compactMap { $0.weight?.w }.max() ?? 0)
        let ladders = [
            Ladder(emoji: "📅", unit: "sessions", value: history.count, steps: [10, 25, 50, 100, 250]),
            Ladder(emoji: "🔥", unit: "week streak", value: streak, steps: [2, 4, 8, 12, 26]),
            Ladder(emoji: "🏋️", unit: "tonnes lifted", value: totalVolume / 1000, steps: [5, 10, 25, 50, 100]),
            Ladder(emoji: "🥇", unit: "kg heaviest lift", value: heaviest, steps: [40, 60, 80, 100, 140]),
        ]

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(back: "Home", title: "🏆 RECORDS", onBack: { appState.screen = .home })

                HStack(spacing: 8) {
                    StatTile(label: "Sessions", value: "\(history.count)")
                    StatTile(label: "Lifted lifetime",
                             value: totalVolume >= 10000 ? "\(Int((Double(totalVolume) / 1000).rounded()))" : String(format: "%.1f", Double(totalVolume) / 1000),
                             unit: "t")
                    StatTile(label: "Week streak", value: "\(streak)")
                }

                CoachCard {
                    CardLabel(text: "Milestones")
                    // one flat list with unique ids ("10 sessions" and "10 tonnes"
                    // must not collide, or the grid drops one and leaves a hole)
                    let badges: [(id: String, emoji: String, text: String, earned: Bool)] = ladders.flatMap { l in
                        l.steps.filter { l.value >= $0 }.map { ("\(l.unit)-\($0)", l.emoji, "\($0) \(l.unit)", true) }
                            + (l.steps.first { l.value < $0 }.map { [("\(l.unit)-next", l.emoji, "\($0) \(l.unit) · \(l.value)/\($0)", false)] } ?? [])
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(badges, id: \.id) { b in badge(b.emoji, b.text, earned: b.earned) }
                    }
                }

                CoachCard {
                    CardLabel(text: "Personal records")
                    if records.isEmpty {
                        Text("Log some weighted sets and your records will appear here.").font(Theme.body(14)).foregroundStyle(Theme.muted)
                    }
                    ForEach(records, id: \.name) { r in
                        let isOpen = openEx == r.name
                        let pts = series.first { $0.name == r.name }?.points ?? []
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.name).font(Theme.body(15, weight: .semibold))
                                Spacer()
                                Text("\(Helpers.fmtKg(r.weight!.w))kg × \(r.weight!.reps.isEmpty ? "?" : r.weight!.reps)")
                                    .font(Theme.mono(14)).foregroundStyle(Theme.amber)
                            }
                            HStack {
                                Text("\(Helpers.fmtDate(r.weight!.date)) · \(r.count) sets logged\(r.e1rm.map { " · est. 1RM \(Helpers.fmtKg($0.v))kg" } ?? "")")
                                    .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                                Spacer()
                                Text(isOpen ? "▾" : "▸").foregroundStyle(Theme.dim)
                            }
                            if isOpen {
                                if pts.count >= 2 {
                                    LineChartView(points: pts.map { ChartPoint(label: Self.shortDate($0.date), value: $0.e ?? $0.w) }, unit: "kg")
                                        .padding(.top, 8)
                                    Text("est. 1RM per session, first → latest").font(Theme.mono(11.5)).foregroundStyle(Theme.dim)
                                } else {
                                    Text("Train it once more to unlock the trend chart.").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { openEx = isOpen ? nil : r.name } }
                        Divider().overlay(Theme.border)
                    }
                }
                Spacer().frame(height: 60)
            }
            .padding(16)
        }
        .coachScreen()
    }

    private func badge(_ emoji: String, _ text: String, earned: Bool) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
            Text(text).font(Theme.mono(12)).foregroundStyle(earned ? Theme.text : Theme.dim).lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(earned ? Theme.amberBg : Theme.bgPill)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(earned ? Theme.amber.opacity(0.6) : Theme.borderDim))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        .opacity(earned ? 1 : 0.7)
    }

    /// "2026-08-30" → "30/8", like the web's toLocaleDateString day/month.
    static func shortDate(_ iso: String) -> String {
        guard let d = Helpers.noonDate(iso) else { return iso }
        return d.formatted(.dateTime.day().month(.defaultDigits))
    }
}

/// `.stat-tile` — small labelled number.
struct StatTile: View {
    let label: String
    let value: String
    var unit = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.head(11.5, weight: .semibold)).textCase(.uppercase).tracking(1).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.head(26, weight: .bold))
                if !unit.isEmpty { Text(unit).font(Theme.body(12)).foregroundStyle(Theme.muted) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
