import SwiftUI

/// Search across the account — ports src/components/Search.jsx:
/// exercises (→ their record), saved workouts (→ the editor) and logged
/// sessions (→ the session). Opened from the tab header's search button.
struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @FocusState private var focused: Bool

    private func sessionName(_ s: Session) -> String {
        let cardio = !s.plan.exercises.isEmpty && s.plan.exercises.allSatisfy { Stats.logMode($0.name, s.plan.sessionType) == "cardio" }
        if cardio { return s.plan.exercises.first?.name ?? s.plan.sessionType }
        return s.plan.title.isEmpty ? s.plan.sessionType : s.plan.title
    }

    var body: some View {
        let term = q.trimmingCharacters(in: .whitespaces).lowercased()
        let has: (String) -> Bool = { $0.lowercased().contains(term) }
        let history = appState.history
        var seen = Set<String>()
        let names = history.flatMap { $0.plan.exercises.map { $0.name.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        let records = Stats.prRecords(history)
        let exercises = term.count < 2 ? [] : names.filter(has)
            .map { n in (n, records.first { $0.name.lowercased() == n.lowercased() }) }
            .sorted { ($0.1?.count ?? 0) > ($1.1?.count ?? 0) }.prefix(5)
        let workouts = term.count < 2 ? [] : Workouts.list().filter { w in has(w.name) || has(w.trainer) || w.exercises.contains { has($0.name) } }.prefix(4)
        let sessions = term.count < 2 ? [] : history.reversed().filter { s in
            has(sessionName(s)) || has(s.plan.sessionType) || has(s.date) || has(Helpers.fmtDate(s.date))
                || has(s.fin?.feedback ?? "") || s.plan.exercises.contains { has($0.name) }
        }.prefix(6)

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: $q, prompt: Text("Exercise, workout or date…").foregroundStyle(Theme.dim))
                        .focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().coachInput()
                        .padding(.bottom, 8)
                    if term.count < 2 {
                        Text("Search exercises, workouts and your log — e.g. “squat”, “push”, “Sept”.").font(Theme.body(13.5)).foregroundStyle(Theme.muted)
                    } else if exercises.isEmpty && workouts.isEmpty && sessions.isEmpty {
                        Text("Nothing matches.").font(Theme.body(13.5)).foregroundStyle(Theme.muted)
                    }
                    if !exercises.isEmpty { group("Exercises") }
                    ForEach(Array(exercises), id: \.0) { name, rec in
                        row(icon: "trophy", title: name, sub: Stats.muscleGroupOf(name) + (rec.map { " · \($0.count) sets logged" } ?? ""),
                            value: rec?.weight.map { "\(Helpers.fmtKg($0.w)) kg × \($0.reps.isEmpty ? "?" : $0.reps)" }) {
                            dismiss(); appState.openRecord(name)
                        }
                    }
                    if !workouts.isEmpty { group("My workouts") }
                    ForEach(Array(workouts)) { w in
                        row(icon: "list.bullet.clipboard", title: w.name,
                            sub: [w.source == "trainer" ? (w.trainer.isEmpty ? "Trainer" : w.trainer) : "Mine", Workouts.daysLabel(w), "\(w.exercises.count) exercises"].filter { !$0.isEmpty }.joined(separator: " · ")) {
                            dismiss(); appState.openWorkouts(id: w.id)
                        }
                    }
                    if !sessions.isEmpty { group("Sessions") }
                    ForEach(Array(sessions), id: \.id) { s in
                        row(icon: "dumbbell", title: sessionName(s),
                            sub: [Helpers.fmtDate(s.date), s.durationMin.map { "\($0) min" }, s.fin.map { "RPE \($0.rpe)" }].compactMap { $0 }.joined(separator: " · ")) {
                            dismiss()
                            appState.detailSession = s
                            appState.screen = .historyDetail
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .coachScreen()
        }
        .onAppear { focused = true }
    }

    private func group(_ title: String) -> some View {
        Text(title).capsLabel(Theme.dim, size: 11).padding(.top, 10).padding(.bottom, 2)
    }

    private func row(icon: String, title: String, sub: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconWell(icon: icon, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(sub).font(Theme.meta(12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                if let value { Text(value).capsLabel(Theme.amberText, size: 13) }
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
