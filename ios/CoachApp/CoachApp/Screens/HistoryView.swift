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
                ScreenHeader(title: "Log", trailing: ("plus", "Add past workout", { appState.screen = .addPast }))

                if rev.isEmpty {
                    Text("Nothing logged yet.")
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
            HStack(alignment: .firstTextBaseline) {
                Text(h.plan.sessionType).font(Theme.head(20, weight: .bold))
                Text(Helpers.fmtDate(h.date)).font(Theme.meta(13)).foregroundStyle(Theme.muted)
                Spacer()
                Button { sheet = SheetState(id: h.id) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 24)
                }
                .accessibilityLabel("Session options")
            }
            // exercise left, sets right — read as one line each
            ForEach(Array(h.plan.exercises.enumerated()), id: \.offset) { exI, ex in
                let sets = (h.log[safe: exI] ?? []).filter(\.isLogged)
                let summary = sets.isEmpty ? "—" : sets.map(\.formatted).joined(separator: "  ")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ex.name).font(Theme.body(14)).foregroundStyle(Theme.textBody).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(summary).font(Theme.meta(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ex.name): \(summary)")
                .accessibilityAddTraits(.isStaticText)
            }
            if let fin = h.fin {
                Text("RPE \(fin.rpe)\(h.durationMin.map { " · \($0) min" } ?? "")")
                    .font(Theme.meta(13)).foregroundStyle(Theme.muted).padding(.top, 2)
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
