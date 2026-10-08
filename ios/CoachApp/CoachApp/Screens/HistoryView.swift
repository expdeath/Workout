import SwiftUI

/// Ports src/screens/History.jsx — every logged session, newest first.
/// Tap → detail; ⋯ → edit sets & notes in place, or delete for good.
struct HistoryView: View {
    @Environment(AppState.self) private var appState

    struct SheetState: Identifiable {
        var id: String
        var deleting = false
    }

    @State private var sheet: SheetState?
    @State private var draft: Session?
    @State private var filter = "all"
    @State private var weekOffset = 0
    @State private var day: String? = nil
    @State private var expanded: Set<String>? = nil

    var body: some View {
        let target = Dashboard.weeklyTarget(LocalStore.shared.backup.aiSettings)
        let rev = Array(appState.history.reversed())
        let shown = rev.filter { h in
            (day == nil || h.date == day) && (filter == "all" || (filter == "cardio") == Self.isCardio(h))
        }
        let open = expanded ?? Self.defaultOpen(rev)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TabHeader(title: "Log")
                monthRow
                weekStrip
                HStack(spacing: 8) {
                    ForEach([("all", "All"), ("strength", "Strength"), ("cardio", "Cardio")], id: \.0) { v, l in
                        Chip(title: l, on: filter == v) { filter = v }
                    }
                    Spacer()
                    if day != nil { Chip(title: "Clear day") { day = nil } }
                }
                weeklyTarget(target)

                if shown.isEmpty {
                    Text(rev.isEmpty ? "Nothing logged yet." : "No sessions here.")
                        .font(Theme.body(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }

                ForEach(shown) { h in
                    if draft?.id == h.id, let d = draft {
                        editCard(d)
                    } else if Self.isCardio(h) {
                        cardioCard(h)
                    } else {
                        sessionCard(h, open: open.contains(h.id))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
        .sheet(item: $sheet) { s in menu(s) }
    }

    // MARK: - Week strip

    private var weekStart: Date {
        let monday = Helpers.noonDate(Stats.mondayOf(Helpers.todayStr())) ?? Date()
        return monday.addingTimeInterval(Double(weekOffset) * 7 * 86400)
    }

    private var monthRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Text(weekStart.formatted(.dateTime.month(.wide).year())).capsLabel(Theme.amberText, size: 14)
                Text("Week \(Calendar(identifier: .iso8601).component(.weekOfYear, from: weekStart))")
                    .font(Theme.meta(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { appState.screen = .addPast } label: { Label("Log workout", systemImage: "plus") }
                .buttonStyle(OutlineButtonStyle())
                .accessibilityLabel("Add past workout")
        }
    }

    private var weekStrip: some View {
        let dates = appState.history.reduce(into: Set<String>()) { $0.insert($1.date) }
        let today = Helpers.todayStr()
        return HStack(spacing: 2) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 22, height: 44) }
                .foregroundStyle(Theme.dim).accessibilityLabel("Previous week")
            ForEach(0..<7, id: \.self) { i in
                let d = weekStart.addingTimeInterval(Double(i) * 86400)
                let iso = Self.iso(d)
                let on = day == iso
                Button { day = on ? nil : iso } label: {
                    VStack(spacing: 5) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).capsLabel(Theme.dim, size: 11)
                        Text(d.formatted(.dateTime.day())).font(Theme.head(18, weight: .bold))
                            .foregroundStyle(on ? Theme.onAmber : (iso == today ? Theme.amberText : Theme.textBody))
                            .frame(width: 32, height: 32)
                            .background(on ? Theme.amber : Color.clear)
                            .overlay(Circle().stroke(iso == today && !on ? Theme.amber.opacity(0.6) : .clear))
                            .clipShape(Circle())
                        Circle().fill(dates.contains(iso) ? Theme.amber : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(iso > today)
                .opacity(iso > today ? 0.35 : 1)
            }
            Button { weekOffset = min(weekOffset + 1, 0) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 44) }
                .foregroundStyle(weekOffset < 0 ? Theme.dim : .clear).disabled(weekOffset >= 0)
                .accessibilityLabel("Next week")
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func weeklyTarget(_ target: Int) -> some View {
        let done = Stats.weekStats(appState.history, target: target).thisWeek
        let pct = min(100, Int((Double(done) / Double(max(target, 1)) * 100).rounded()))
        return CoachCard(padding: 14) {
            HStack {
                Text("Weekly target").capsLabel()
                Spacer()
                Text("\(pct)% complete").capsLabel(pct >= 100 ? Theme.green : Theme.amberText, size: 12)
            }
            ProgressLine(fraction: Double(pct) / 100, color: pct >= 100 ? Theme.green : Theme.amber, height: 7)
            HStack {
                Text("\(done) of \(target) sessions finished")
                Spacer()
                Text(done >= target ? "Target hit" : "\(target - done) to go")
            }
            .font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
        }
    }

    static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: d)
    }

    /// The three newest sessions start expanded; older ones are folded.
    static func defaultOpen(_ newestFirst: [Session]) -> Set<String> {
        Set(newestFirst.prefix(3).map(\.id))
    }

    /// Every exercise in it is logged as time/distance (quick cardio, a run…).
    static func isCardio(_ h: Session) -> Bool {
        !h.plan.exercises.isEmpty && h.plan.exercises.allSatisfy { Stats.logMode($0.name, h.plan.sessionType) == "cardio" }
    }

    // MARK: - Read-only cards

    private func cardHeader(_ h: Session, icon: String, open: Bool?) -> some View {
        HStack(spacing: 12) {
            IconWell(icon: icon, tint: Self.isCardio(h) ? Theme.green : Theme.amberText)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.isCardio(h) ? (h.plan.exercises.first?.name ?? h.plan.sessionType) : h.plan.sessionType)
                    .font(Theme.body(17, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text([Helpers.fmtDate(h.date), h.durationMin.map { "\($0) min" }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.meta(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let open {
                Button { toggle(h.id) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30).background(Theme.bgHigh).clipShape(Circle())
                }
                .accessibilityLabel(open ? "Collapse" : "Expand")
            }
            Button { sheet = SheetState(id: h.id) } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Session options")
        }
    }

    private func toggle(_ id: String) {
        var open = expanded ?? Self.defaultOpen(appState.history.reversed())
        if open.contains(id) { open.remove(id) } else { open.insert(id) }
        withAnimation(.easeOut(duration: 0.2)) { expanded = open }
    }

    private func sessionCard(_ h: Session, open: Bool) -> some View {
        let sets = h.log.flatMap { $0.filter(\.isLogged) }
        return CoachCard {
            cardHeader(h, icon: "dumbbell.fill", open: open)
            HStack(spacing: 0) {
                stat("Volume", "\(Stats.sessionVolume(h).formatted()) kg")
                stat("Sets", "\(sets.count)")
                stat("Effort", h.fin.map { "RPE \($0.rpe)" } ?? "—", color: Theme.amberText)
            }
            .padding(.vertical, 8)
            .background(Theme.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            if open {
                ForEach(Array(h.plan.exercises.enumerated()), id: \.offset) { exI, ex in
                    let logged = (h.log[safe: exI] ?? []).filter(\.isLogged)
                    let all = logged.isEmpty ? "—" : logged.map(\.formatted).joined(separator: "  ")
                    let best = logged.max { (Double($0.weight) ?? 0) < (Double($1.weight) ?? 0) }
                    HStack(spacing: 10) {
                        Circle().fill(Theme.amber).frame(width: 6, height: 6)
                        Text(ex.name).font(Theme.body(14.5)).foregroundStyle(Theme.textBody).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(best.map { Self.setShort($0) } ?? "—").font(Theme.head(17, weight: .bold)).foregroundStyle(Theme.amberText)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.bgPill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(ex.name): \(all)")
                    .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.detailSession = h
            appState.screen = .historyDetail
        }
    }

    private func stat(_ label: String, _ value: String, color: Color = Theme.text) -> some View {
        VStack(spacing: 2) {
            Text(label).capsLabel(Theme.dim, size: 10.5)
            Text(value).font(Theme.head(17, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// 24kg×11 → "24kg × 11"; a tick-off set → "✓"
    static func setShort(_ s: SetLog) -> String {
        if !s.weight.isEmpty || !s.reps.isEmpty { return "\(s.weight.isEmpty ? "—" : s.weight + "kg") × \(s.reps.isEmpty ? "?" : s.reps)" }
        return s.formatted
    }

    private func cardioCard(_ h: Session) -> some View {
        let sets = h.log.flatMap { $0.filter(\.isLogged) }
        let km = sets.compactMap { Double($0.dist) }.reduce(0, +)
        let min = sets.compactMap { Double($0.time) }.reduce(0, +)
        let name = (h.plan.exercises.first?.name ?? "").lowercased()
        let icon = name.contains("cycl") || name.contains("ride") || name.contains("bike") ? "bicycle"
            : name.contains("hike") ? "figure.hiking" : name.contains("walk") ? "figure.walk" : "figure.run"
        return CoachCard {
            HStack(spacing: 12) {
                IconWell(icon: icon, tint: Theme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.plan.exercises.first?.name ?? h.plan.sessionType).font(Theme.body(17, weight: .bold)).lineLimit(1)
                    Text([Helpers.fmtDate(h.date), min > 0 ? "\(Helpers.fmtKg(min)) min" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.meta(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(km > 0 ? "\(Helpers.fmtKg(km)) km" : "\(Helpers.fmtKg(min)) min").font(Theme.head(20, weight: .bold))
                    if let f = h.fin { Text("RPE \(f.rpe)").capsLabel(Theme.green, size: 11) }
                }
                Button { sheet = SheetState(id: h.id) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 30)
                }
                .accessibilityLabel("Session options")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.detailSession = h
                appState.screen = .historyDetail
            }
        }
    }

    // MARK: - Edit in place

    private func editCard(_ d: Session) -> some View {
        CoachCard {
            HStack {
                Text(d.plan.sessionType).font(Theme.head(18, weight: .bold))
                Spacer()
                Text(Helpers.fmtDate(d.date)).font(Theme.meta(13)).foregroundStyle(Theme.muted)
            }
            ForEach(Array(d.plan.exercises.enumerated()), id: \.offset) { exI, ex in
                Text(ex.name).font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.textBody).padding(.top, 8)
                let mode = Stats.logMode(ex.name, d.plan.sessionType)
                ForEach(Array((d.log[safe: exI] ?? []).enumerated()), id: \.offset) { setI, s in
                    HStack(spacing: 8) {
                        Text("\(setI + 1)").font(Theme.meta(13)).foregroundStyle(Theme.muted).frame(width: 20)
                        switch mode {
                        case "check":
                            Text(s.done ? "Done" : "Skipped").font(Theme.body(13)).foregroundStyle(Theme.muted)
                        case "cardio":
                            SetField(value: s.time, placeholder: "min") { edit(exI, setI) { $0.time = Helpers.cleanTime($1) }($0) }
                            Text("min").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                            SetField(value: s.dist, placeholder: "km") { edit(exI, setI) { $0.dist = Helpers.cleanDist($1) }($0) }
                            Text("km").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                        default:
                            SetField(value: s.weight, placeholder: "kg") { edit(exI, setI) { $0.weight = Helpers.cleanWeight($1) }($0) }
                            Text("×").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                            SetField(value: s.reps, placeholder: "reps", decimal: false) { edit(exI, setI) { $0.reps = Helpers.cleanReps($1) }($0) }
                        }
                        Spacer()
                    }
                }
            }
            Text("Session RPE").font(Theme.meta(13)).foregroundStyle(Theme.muted).padding(.top, 10)
            SetField(value: d.fin.map { String($0.rpe) } ?? "", placeholder: "1-10", decimal: false) { v in
                let n = Int(v.filter(\.isNumber)) ?? 0
                draft?.fin = draft?.fin ?? FinishInfo()
                draft?.fin?.rpe = min(max(n, 1), 10)
            }
            TextField("", text: Binding(get: { draft?.fin?.pain ?? "" }, set: { draft?.fin = draft?.fin ?? FinishInfo(); draft?.fin?.pain = $0 }),
                      prompt: Text("Pain (empty = none)").foregroundStyle(Theme.dim))
                .coachInput()
            TextField("", text: Binding(get: { draft?.fin?.feedback ?? "" }, set: { draft?.fin = draft?.fin ?? FinishInfo(); draft?.fin?.feedback = $0 }),
                      prompt: Text("Feedback").foregroundStyle(Theme.dim))
                .coachInput()
            HStack(spacing: 10) {
                Button("Save changes") {
                    if let d = draft {
                        // only what this form edits (sets + RPE/pain/feedback),
                        // onto the latest copy — a debrief or another device's
                        // change that arrived while editing must survive
                        var latest = LocalStore.shared.backup.sessions.first { $0.id == d.id } ?? d
                        latest.log = d.log
                        latest.fin = d.fin
                        Task { await appState.updateSession(latest) }
                    }
                    draft = nil
                }
                .buttonStyle(BigButtonStyle())
                Button("Cancel") { draft = nil }
                    .font(Theme.head(15, weight: .semibold)).textCase(.uppercase).foregroundStyle(Theme.muted)
            }
            .padding(.top, 12)
        }
    }

    /// Returns a setter that edits one set of the draft.
    private func edit(_ exI: Int, _ setI: Int, _ apply: @escaping (inout SetLog, String) -> Void) -> (String) -> Void {
        { v in
            guard var d = draft, exI < d.log.count, setI < d.log[exI].count else { return }
            apply(&d.log[exI][setI], v)
            draft = d
        }
    }

    // MARK: - ⋯ sheet

    @ViewBuilder
    private func menu(_ s: SheetState) -> some View {
        let h = appState.history.first { $0.id == s.id }
        VStack(alignment: .leading, spacing: 4) {
            Text("\(h?.plan.sessionType ?? "Session") · \(Helpers.fmtDate(h?.date ?? ""))")
                .font(Theme.head(20, weight: .bold)).padding(.bottom, 8)
            if !s.deleting {
                sheetButton("Edit", icon: "pencil") { draft = h; sheet = nil }
                sheetButton("Delete", icon: "trash", color: Theme.red) { sheet = SheetState(id: s.id, deleting: true) }
            } else {
                Text("Delete for good? It's removed from your log, stats and the coach's memory.")
                    .font(Theme.body(14)).foregroundStyle(Theme.muted)
                Button("Delete") {
                    sheet = nil
                    if let h { Task { await appState.deleteSession(h) } }
                }
                .buttonStyle(BigButtonStyle(danger: true))
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachScreen()
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private func sheetButton(_ title: String, icon: String, color: Color = Theme.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: icon).frame(width: 24) }
                .font(Theme.body(16)).foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
