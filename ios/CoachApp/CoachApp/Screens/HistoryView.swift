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

    var body: some View {
        let rev = Array(appState.history.reversed())
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(back: "Home", title: "LOG", onBack: { appState.screen = .home },
                             trailing: ("+ Past", { appState.screen = .addPast }))

                if rev.isEmpty {
                    Text("Nothing logged yet.\nYour first session will show up here — and every one after it makes the coach smarter.")
                        .font(Theme.body(15)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 80)
                }

                ForEach(rev) { h in
                    if draft?.id == h.id, let d = draft {
                        editCard(d)
                    } else {
                        sessionCard(h)
                    }
                }
                Spacer().frame(height: 24)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
        .sheet(item: $sheet) { s in menu(s) }
    }

    // MARK: - Read-only card

    private func sessionCard(_ h: Session) -> some View {
        CoachCard {
            HStack {
                Text(h.plan.sessionType).font(Theme.head(18, weight: .bold))
                + Text(" ›").font(Theme.body(14)).foregroundStyle(Theme.dim)
                Spacer()
                Text(Helpers.fmtDate(h.date)).font(Theme.mono(13)).foregroundStyle(Theme.muted)
                Button { sheet = SheetState(id: h.id) } label: {
                    Text("⋯").font(Theme.head(20, weight: .bold)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
                .accessibilityLabel("Session options")
            }
            ForEach(Array(h.plan.exercises.enumerated()), id: \.offset) { exI, ex in
                let sets = (h.log[safe: exI] ?? []).filter(\.isLogged)
                Text("\(ex.name): \(sets.isEmpty ? "—" : sets.map(\.formatted).joined(separator: "  "))")
                    .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            }
            if let fin = h.fin {
                Text("RPE \(fin.rpe)/10\(h.durationMin.map { " · \($0)min" } ?? "")")
                    .font(Theme.mono(13)).foregroundStyle(Theme.amber).padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.detailSession = h
            appState.screen = .historyDetail
        }
    }

    // MARK: - Edit in place

    private func editCard(_ d: Session) -> some View {
        CoachCard {
            HStack {
                Text(d.plan.sessionType).font(Theme.head(18, weight: .bold))
                Spacer()
                Text(Helpers.fmtDate(d.date)).font(Theme.mono(13)).foregroundStyle(Theme.muted)
            }
            ForEach(Array(d.plan.exercises.enumerated()), id: \.offset) { exI, ex in
                Text(ex.name).font(Theme.mono(13)).foregroundStyle(Theme.textBody).padding(.top, 8)
                let mode = Stats.logMode(ex.name, d.plan.sessionType)
                ForEach(Array((d.log[safe: exI] ?? []).enumerated()), id: \.offset) { setI, s in
                    HStack(spacing: 8) {
                        Text("\(setI + 1)").font(Theme.mono(13)).foregroundStyle(Theme.muted).frame(width: 20)
                        switch mode {
                        case "check":
                            Text(s.done ? "✓ done" : "— skipped").font(Theme.body(13)).foregroundStyle(Theme.muted)
                        case "cardio":
                            SetField(value: s.time, placeholder: "min") { edit(exI, setI) { $0.time = Helpers.cleanTime($1) }($0) }
                            Text("min").font(Theme.mono(13)).foregroundStyle(Theme.muted)
                            SetField(value: s.dist, placeholder: "km") { edit(exI, setI) { $0.dist = Helpers.cleanDist($1) }($0) }
                            Text("km").font(Theme.mono(13)).foregroundStyle(Theme.muted)
                        default:
                            SetField(value: s.weight, placeholder: "kg") { edit(exI, setI) { $0.weight = Helpers.cleanWeight($1) }($0) }
                            Text("×").font(Theme.mono(13)).foregroundStyle(Theme.muted)
                            SetField(value: s.reps, placeholder: "reps", decimal: false) { edit(exI, setI) { $0.reps = Helpers.cleanReps($1) }($0) }
                        }
                        Spacer()
                    }
                }
            }
            Text("Session RPE").font(Theme.mono(13)).foregroundStyle(Theme.muted).padding(.top, 10)
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
                    if let d = draft { Task { await appState.updateSession(d) } }
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
                sheetButton("✎ Edit sets & notes") { draft = h; sheet = nil }
                sheetButton("✕ Delete session", color: Theme.red) { sheet = SheetState(id: s.id, deleting: true) }
            } else {
                Text("Delete this session for good? It disappears from your log, stats, and the coach's memory.")
                    .font(Theme.body(14)).foregroundStyle(Theme.muted)
                Button("✕ Delete it") {
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

    private func sheetButton(_ title: String, color: Color = Theme.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.body(16)).foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
