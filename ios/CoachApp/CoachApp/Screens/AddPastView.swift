import SwiftUI

/// Ports src/screens/AddPast.jsx — log a workout after the fact. No
/// check-in, no AI: pick the day and type, type in what you did. Saved
/// as a finished session on that date.
struct AddPastView: View {
    @Environment(AppState.self) private var appState

    private static let types = ["Push", "Pull", "Legs", "Full Body", "Core", "Cardio", "Stretch & Mobility"]

    struct DraftExercise {
        var name = ""
        var sets: [SetLog] = [SetLog(), SetLog(), SetLog()]
    }

    @State private var date = Helpers.daysAgoStr(1)
    @State private var sessionType = "Full Body"
    @State private var exercises = [DraftExercise()]
    @State private var durationMin = ""
    @State private var rpe = 7
    @State private var feedback = ""
    @State private var error = ""
    @State private var nameFocus: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Past workout", onBack: { appState.screen = .history })

                QLabel(text: "Day", value: Helpers.fmtDate(date))
                SegGroup(options: [("1", "Yesterday"), ("2", "2 days ago"), ("3", "3 days ago")],
                         value: Binding(get: { ["1", "2", "3"].first { Helpers.daysAgoStr(Int($0)!) == date } ?? "" },
                                        set: { date = Helpers.daysAgoStr(Int($0) ?? 1) }))
                DatePicker("Other day", selection: Binding(get: { Self.parse(date) }, set: { date = Self.iso($0) }),
                           in: ...Date(), displayedComponents: .date)
                    .font(Theme.body(15)).foregroundStyle(Theme.muted)
                    .padding(.top, 8)

                QLabel(text: "Type")
                SegGroup(options: Self.types.map { ($0, $0) }, value: $sessionType, columns: 3)

                HStack {
                    QLabel(text: "Exercises")
                    if let last = lastOfType {
                        Button("Copy last \(sessionType)") { copyFrom(last) }
                            .font(Theme.body(13.5, weight: .medium)).foregroundStyle(Theme.teal)
                            .padding(.top, 14)
                    }
                }

                ForEach(exercises.indices, id: \.self) { exI in exerciseCard(exI) }

                Button { exercises.append(DraftExercise()) } label: {
                    Label("Add exercise", systemImage: "plus").font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }

                QLabel(text: "Duration")
                HStack {
                    SetField(value: durationMin, placeholder: "min") { durationMin = Helpers.cleanTime($0) }
                    Text("min").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                }

                QLabel(text: "Effort (RPE)", value: "\(rpe)/10")
                Slider(value: Binding(get: { Double(rpe) }, set: { rpe = Int($0) }), in: 1...10, step: 1).tint(Theme.amber)
                TextField("", text: $feedback, prompt: Text("Notes").foregroundStyle(Theme.dim))
                    .coachInput().padding(.top, 8)

                if !error.isEmpty { ErrorBox(text: error).padding(.top, 12) }

                Button("Save") { save() }
                    .buttonStyle(BigButtonStyle()).padding(.top, 18)
                Spacer().frame(height: 24)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
    }

    // MARK: - Pieces

    private func exerciseCard(_ exI: Int) -> some View {
        let ex = exercises[exI]
        let mode = Stats.logMode(ex.name, sessionType)
        return CoachCard {
            TextField("", text: Binding(get: { exercises[exI].name }, set: { exercises[exI].name = $0 }),
                      prompt: Text("Exercise").foregroundStyle(Theme.dim))
                .coachInput()
                .onTapGesture { nameFocus = exI }
            // exercise names you've logged before — so names match and
            // progressions line up (the web's <datalist>)
            if nameFocus == exI {
                let matches = suggestions(for: ex.name)
                if !matches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(matches, id: \.self) { n in Chip(title: n) { exercises[exI].name = n; nameFocus = nil } } }
                    }
                }
            }
            ForEach(ex.sets.indices, id: \.self) { setI in
                let s = ex.sets[setI]
                HStack(spacing: 8) {
                    Text("\(setI + 1)").font(Theme.meta(13)).foregroundStyle(Theme.muted).frame(width: 20)
                    switch mode {
                    case "check":
                        Button { exercises[exI].sets[setI].done.toggle() } label: {
                            Text(s.done ? "✓" : " ").font(Theme.meta(14, weight: .medium)).frame(width: 34, height: 34)
                                .foregroundStyle(Theme.bg).background(s.done ? Theme.teal : Theme.bgPill)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                        }
                        .accessibilityLabel(s.done ? "Mark not done" : "Mark done")
                    case "cardio":
                        SetField(value: s.time, placeholder: "min") { exercises[exI].sets[setI].time = Helpers.cleanTime($0) }
                        Text("min").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                        SetField(value: s.dist, placeholder: "km") { exercises[exI].sets[setI].dist = Helpers.cleanDist($0) }
                        Text("km").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                    default:
                        SetField(value: s.weight, placeholder: "kg") { exercises[exI].sets[setI].weight = Helpers.cleanWeight($0) }
                        Text("×").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                        SetField(value: s.reps, placeholder: "reps", decimal: false) { exercises[exI].sets[setI].reps = Helpers.cleanReps($0) }
                    }
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                link("Add set") { exercises[exI].sets.append(SetLog()) }
                if ex.sets.count > 1 { link("Remove set") { exercises[exI].sets.removeLast() } }
                Spacer()
                if exercises.count > 1 { link("Delete", color: Theme.red) { exercises.remove(at: exI) } }
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 10)
    }

    private func link(_ t: String, color: Color = Theme.teal, _ action: @escaping () -> Void) -> some View {
        Button(t, action: action).font(Theme.body(13.5, weight: .medium)).foregroundStyle(color)
    }

    /// Names logged before, most recent first, filtered by what's typed.
    private func suggestions(for typed: String) -> [String] {
        var seen = Set<String>(), names: [String] = []
        for s in appState.history.reversed() {
            for ex in s.plan.exercises {
                let n = ex.name.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty, seen.insert(n.lowercased()).inserted { names.append(n) }
            }
        }
        let q = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return Array(names.filter { q.isEmpty || ($0.lowercased().contains(q) && $0.lowercased() != q) }.prefix(8))
    }

    /// Most recent session of this type up to the chosen day.
    private var lastOfType: Session? {
        appState.history.reversed().first { $0.plan.sessionType == sessionType && $0.date <= date && !$0.plan.exercises.isEmpty }
    }

    private func copyFrom(_ s: Session) {
        exercises = s.plan.exercises.enumerated().map { i, ex in
            let sets = (s.log[safe: i] ?? []).filter(\.isLogged)
            return DraftExercise(name: ex.name, sets: sets.isEmpty ? [SetLog()] : sets)
        }
        error = ""
    }

    private func save() {
        guard date <= Helpers.todayStr() else { error = "Pick a day on or before today."; return }
        var plan: [Plan.Exercise] = [], log: [[SetLog]] = []
        for ex in exercises {
            let name = String(ex.name.trimmingCharacters(in: .whitespaces).prefix(60))
            guard !name.isEmpty else { continue }
            let mode = Stats.logMode(name, sessionType)
            // keep only the fields this kind of exercise logs, and only
            // sets that actually happened
            let sets: [SetLog] = ex.sets.compactMap { s in
                switch mode {
                case "cardio": return (s.time.isEmpty && s.dist.isEmpty) ? nil : SetLog(done: true, time: s.time, dist: s.dist)
                case "check": return s.done ? SetLog(done: true) : nil
                default: return (s.weight.isEmpty && s.reps.isEmpty) ? nil : SetLog(weight: s.weight, reps: s.reps, done: true)
                }
            }
            guard !sets.isEmpty else { continue }
            let reps = sets.compactMap { Int($0.reps) }.filter { $0 > 0 }
            let repsText = reps.isEmpty ? "" : (reps.min() == reps.max() ? "\(reps[0])" : "\(reps.min()!)-\(reps.max()!)")
            plan.append(Plan.Exercise(name: name, sets: sets.count, reps: repsText))
            log.append(sets)
        }
        guard !plan.isEmpty else { error = "Add at least one exercise with a logged set."; return }
        let minutes = Int((Double(durationMin) ?? 0).rounded())
        appState.addPastSession(date: date, sessionType: sessionType, exercises: plan, log: log,
                                durationMin: minutes > 0 ? minutes : nil, rpe: rpe,
                                feedback: feedback.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parse(_ iso: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: iso) ?? Date()
    }

    private static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: d)
    }
}
