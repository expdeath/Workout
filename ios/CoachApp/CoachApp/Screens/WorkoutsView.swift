import SwiftUI
import PhotosUI

/// My workouts — ports src/screens/Workouts.jsx: the saved-workout
/// library (yours and your trainer's), the weekday schedule, daily
/// add-ons, and the coach that builds them from a program, a photo of
/// one, or a description. Everything is account state in Firestore
/// (Models/SavedWorkout.swift), shared with the web app.
struct WorkoutsView: View {
    @Environment(AppState.self) private var appState
    let openId: String?

    enum Mode { case list, edit, build, review }
    @State private var mode: Mode = .list
    @State private var draft = SavedWorkout()
    @State private var drafts: [SavedWorkout] = []
    @State private var coachMsg = ""
    @State private var confirmDel: String? = nil

    init(openId: String?) {
        self.openId = openId
        if let id = openId, let w = Workouts.get(id) {
            _mode = State(initialValue: .edit)
            _draft = State(initialValue: w)
        }
    }

    private static func newDraft() -> SavedWorkout {
        SavedWorkout(exercises: [SavedWorkout.Exercise()])
    }

    var body: some View {
        _ = appState.stateTick // re-read the library when another device changes it
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch mode {
                case .list: list
                case .edit: WorkoutEditor(draft: $draft, onSave: save, onCancel: { mode = .list })
                case .build: WorkoutBuilder(history: appState.history, onBack: { mode = .list }) { res in
                    drafts = res.workouts
                    coachMsg = res.message
                    mode = .review
                }
                case .review: review
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
    }

    private var title: String {
        switch mode {
        case .list: return "My workouts"
        case .edit: return draft.id.isEmpty ? "New workout" : "Edit workout"
        case .build: return "Build with coach"
        case .review: return "Review"
        }
    }

    private func back() {
        switch mode {
        case .list: appState.screen = appState.workoutsFrom
        case .review: mode = .build
        default: mode = .list
        }
    }

    private func save() {
        let saved = Workouts.save(draft)
        LocalStore.shared.logEvent(type: "workout_saved", data: [
            "id": .string(saved.id), "kind": .string(saved.kind), "source": .string(saved.source),
            "exercises": .number(Double(saved.exercises.count)), "days": .number(Double(saved.days.count)),
        ])
        mode = .list
    }

    // MARK: - Library

    @ViewBuilder private var list: some View {
        let all = Workouts.list()
        ScreenHeader(title: title, onBack: back)
        HStack(spacing: 8) {
            Button { mode = .build } label: { Label("Build with coach", systemImage: "brain.head.profile") }
                .buttonStyle(BigButtonStyle())
            Button { draft = Self.newDraft(); mode = .edit } label: { Label("New", systemImage: "plus").frame(maxHeight: .infinity) }
                .buttonStyle(OutlineButtonStyle())
                .frame(width: 96)
        }
        .fixedSize(horizontal: false, vertical: true)

        if all.contains(where: { !$0.days.isEmpty || $0.isAddOn }) { WeekPlan(all: all) }

        if all.isEmpty {
            CoachCard {
                Text("No saved workouts yet").font(Theme.head(22, weight: .bold)).textCase(.uppercase)
                Text("Snap a photo of your trainer's program, paste it, or tell the coach what you want — it turns it into workouts you can schedule and start in one tap.")
                    .font(Theme.body(14)).foregroundStyle(Theme.muted)
            }
        }
        let sessions = all.filter { !$0.isAddOn }
        let addOns = all.filter(\.isAddOn)
        if !sessions.isEmpty { SectionHead(title: "Workouts") }
        ForEach(sessions) { card($0) }
        if !addOns.isEmpty { SectionHead(title: "Add-ons", trailing: "On their days", trailingColor: Theme.muted) }
        ForEach(addOns) { card($0) }
    }

    private func card(_ w: SavedWorkout) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(w.name).font(Theme.head(22, weight: .bold)).textCase(.uppercase)
                    WorkoutBadges(w: w)
                }
                Spacer()
                if !w.isAddOn {
                    Button {
                        Task { await appState.startSavedWorkout(w.id) }
                    } label: { Label("Start", systemImage: "arrow.right").labelStyle(TrailingIconLabel()) }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            ExerciseSummary(exercises: w.exercises, max: 4)
            HStack(spacing: 18) {
                Button { draft = w; mode = .edit } label: { Label("Edit", systemImage: "pencil") }
                if confirmDel == w.id {
                    Button("Tap again to delete") { Workouts.delete(w.id); confirmDel = nil }.foregroundStyle(Theme.red)
                } else {
                    Button { confirmDel = w.id } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .font(Theme.body(13.5)).foregroundStyle(Theme.muted).padding(.top, 4)
        }
    }

    // MARK: - Review what the coach built

    @ViewBuilder private var review: some View {
        ScreenHeader(title: title, onBack: back)
        if !coachMsg.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                IconWell(icon: "brain.head.profile", size: 32)
                Text(coachMsg).font(Theme.body(14)).foregroundStyle(Theme.textBody)
            }
            .padding(12).background(Theme.bgCard).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        ForEach(drafts.indices, id: \.self) { i in
            CoachCard {
                HStack {
                    TextField("", text: $drafts[i].name).font(Theme.body(16, weight: .semibold)).coachInput()
                    IconButton(icon: "xmark", label: "Remove") { drafts.remove(at: i) }
                }
                KindAndDays(w: $drafts[i])
                ExerciseSummary(exercises: drafts[i].exercises)
            }
        }
        Button(drafts.count > 1 ? "Save all \(drafts.count)" : "Save workout") {
            drafts.forEach { Workouts.save($0) }
            LocalStore.shared.logEvent(type: "workouts_imported", data: ["count": .number(Double(drafts.count)), "source": .string(drafts.first?.source ?? "")])
            drafts = []
            mode = .list
        }
        .buttonStyle(BigButtonStyle())
        .disabled(drafts.isEmpty)
        Button("Start over") { mode = .build }
            .font(Theme.body(14, weight: .medium)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
        Text("You can change anything later — open a workout and edit it.").font(Theme.meta(12.5)).foregroundStyle(Theme.dim)
    }
}

/// Label with the icon after the text ("Start →").
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// Trainer · Kept exact / Coach adapts · Mon · Wed
struct WorkoutBadges: View {
    let w: SavedWorkout
    var body: some View {
        HStack(spacing: 6) {
            if w.source == "trainer" { StatusPill(text: w.trainer.isEmpty ? "Trainer" : "Trainer · \(w.trainer)", color: Theme.green, dot: false).fixedSize() }
            if !w.isAddOn { StatusPill(text: w.adapt ? "Coach adapts" : "Kept exact", color: Theme.amberText, dot: false).fixedSize() }
            let days = Workouts.daysLabel(w)
            Text(days.isEmpty ? "Not scheduled" : days).capsLabel(days.isEmpty ? Theme.dim : Theme.textBody, size: 11).lineLimit(1)
        }
    }
}

struct ExerciseSummary: View {
    let exercises: [SavedWorkout.Exercise]
    var max = 99
    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(exercises.prefix(max).enumerated()), id: \.offset) { _, e in
                HStack {
                    Text(e.name).font(Theme.body(14)).lineLimit(1)
                    Spacer()
                    Text("\(e.sets) × \(e.reps)\(e.weight.isEmpty ? "" : " · \(e.weight)")").capsLabel(Theme.amberText, size: 13)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.bgPill).clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            }
            if exercises.count > max {
                Text("+\(exercises.count - max) more").font(Theme.meta(12.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Mon–Sun: what's scheduled each day (add-ons as a green dot).
struct WeekPlan: View {
    let all: [SavedWorkout]
    var body: some View {
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        HStack(alignment: .top, spacing: 4) {
            ForEach(Workouts.weekOrder, id: \.self) { d in
                let s = all.filter { !$0.isAddOn && $0.days.contains(d) }
                let a = all.filter { $0.isAddOn && ($0.days.isEmpty || $0.days.contains(d)) }
                VStack(spacing: 4) {
                    Text(Workouts.weekdays[d]).capsLabel(d == today ? Theme.amberText : Theme.muted, size: 11)
                    ForEach(s) { Text($0.name).font(Theme.body(11, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2) }
                    if !a.isEmpty { Circle().fill(Theme.green).frame(width: 6, height: 6) }
                    if s.isEmpty && a.isEmpty { Text("—").font(Theme.meta(12)).foregroundStyle(Theme.dim) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(d == today ? Theme.amberBg : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            }
        }
        .padding(8)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// Workout / daily add-on, and the weekdays it's on.
struct KindAndDays: View {
    @Binding var w: SavedWorkout
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegGroup(options: [("session", "Workout"), ("addon", "Daily add-on")], value: $w.kind)
            HStack(spacing: 5) {
                ForEach(Workouts.weekOrder, id: \.self) { d in
                    Chip(title: Workouts.weekdays[d], on: w.days.contains(d)) {
                        if let i = w.days.firstIndex(of: d) { w.days.remove(at: i) } else { w.days.append(d) }
                    }
                }
            }
            Text(w.isAddOn
                 ? (w.days.isEmpty ? "No days picked = added to every session." : "Added to your session on these days.")
                 : (w.days.isEmpty ? "Not scheduled — start it from here or the check-in whenever you like." : "Ready to start on these days — Today shows it."))
                .font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
        }
    }
}

struct WorkoutEditor: View {
    @Binding var draft: SavedWorkout
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScreenHeader(title: draft.id.isEmpty ? "New workout" : "Edit workout", onBack: onCancel)
        CoachCard {
            QLabel(text: "Name").padding(.top, -12)
            TextField("", text: $draft.name, prompt: Text("e.g. Upper A, Leg day, Daily core").foregroundStyle(Theme.dim)).coachInput()
            KindAndDays(w: $draft).padding(.top, 4)
            QLabel(text: "Who wrote it?")
            SegGroup(options: [("me", "Me"), ("trainer", "My trainer")], value: $draft.source)
            if draft.source == "trainer" {
                TextField("", text: $draft.trainer, prompt: Text("Trainer's name (optional)").foregroundStyle(Theme.dim)).coachInput()
            }
            if !draft.isAddOn {
                Toggle(isOn: $draft.adapt) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let the coach adapt it").font(Theme.body(15, weight: .medium))
                        Text(draft.adapt
                             ? "On a tired or sore day the coach may ease or trim it, and tells you what changed."
                             : "Off: kept exactly as written — the coach only fills in weights and flags recovery.")
                            .font(Theme.meta(12.5)).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.amber).padding(.top, 10)
            }
            QLabel(text: "Notes")
            TextField("", text: $draft.notes, prompt: Text("Tempo, warm-up, the trainer's instructions…").foregroundStyle(Theme.dim), axis: .vertical)
                .lineLimit(2...5).coachInput()
        }
        CoachCard {
            HStack {
                Text("Exercises").capsLabel()
                Spacer()
                Text("Weight empty = from history").capsLabel(Theme.dim, size: 10.5)
            }
            ForEach(draft.exercises.indices, id: \.self) { i in
                if i > 0 { Divider().overlay(Theme.border).padding(.vertical, 4) }
                exerciseRow(i)
            }
            Button { draft.exercises.append(SavedWorkout.Exercise()) } label: { Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(OutlineButtonStyle()).padding(.top, 6)
        }
        Button("Save workout", action: onSave)
            .buttonStyle(BigButtonStyle())
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || !draft.exercises.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    private func exerciseRow(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text("\(i + 1)").capsLabel(Theme.amberText).frame(width: 20, alignment: .leading)
                TextField("", text: $draft.exercises[i].name, prompt: Text("Exercise").foregroundStyle(Theme.dim)).coachInput()
                IconButton(icon: "chevron.up", label: "Move up") { move(i, -1) }.disabled(i == 0).frame(width: 30)
                IconButton(icon: "chevron.down", label: "Move down") { move(i, 1) }.disabled(i == draft.exercises.count - 1).frame(width: 30)
                IconButton(icon: "xmark", label: "Remove exercise") { draft.exercises.remove(at: i) }.frame(width: 30)
            }
            HStack(spacing: 6) {
                small("Sets", Binding(get: { String(draft.exercises[i].sets) }, set: { draft.exercises[i].sets = Int($0.filter(\.isNumber).prefix(2)) ?? 3 }), "3", numeric: true)
                small("Reps", $draft.exercises[i].reps, "8-10")
                small("Weight", $draft.exercises[i].weight, "auto")
                small("Rest", $draft.exercises[i].rest, "90s")
            }
            TextField("", text: $draft.exercises[i].notes, prompt: Text("Cue or note (optional)").foregroundStyle(Theme.dim))
                .font(Theme.body(14)).padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.bgInput).clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
    }

    private func small(_ label: String, _ text: Binding<String>, _ placeholder: String, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).capsLabel(Theme.dim, size: 10.5)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
                .keyboardType(numeric ? .numberPad : .default)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(Theme.body(14)).padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.bgInput).clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
    }

    private func move(_ i: Int, _ dir: Int) {
        let j = i + dir
        guard draft.exercises.indices.contains(j) else { return }
        draft.exercises.swapAt(i, j)
    }
}

/// Paste a program, add a photo of it, or describe what you want.
struct WorkoutBuilder: View {
    let history: [Session]
    let onBack: () -> Void
    let onBuilt: ((workouts: [SavedWorkout], message: String)) -> Void

    @State private var source = "trainer"
    @State private var trainer = ""
    @State private var text = ""
    @State private var pick: PhotosPickerItem? = nil
    @State private var photo: UIImage? = nil
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        ScreenHeader(title: "Build with coach", onBack: onBack)
        CoachCard {
            SegGroup(options: [("trainer", "From my trainer"), ("me", "Describe it")], value: $source)
            Text(source == "trainer"
                 ? "Paste the program your trainer sent, or add a photo of it. The coach copies it exactly — every exercise, set and rep — and splits a multi-day plan into separate workouts."
                 : "Tell the coach what you want, e.g. “15 minutes of core every day” or “upper body with dumbbells, 45 min, Mon and Thu”. It builds it around your goals, equipment and history.")
                .font(Theme.body(13.5)).foregroundStyle(Theme.muted)
            if source == "trainer" {
                TextField("", text: $trainer, prompt: Text("Trainer's name (optional)").foregroundStyle(Theme.dim)).coachInput()
            }
            TextField("", text: $text, prompt: Text(source == "trainer" ? "Day A — Mon\nBench press 4x6 @ 70kg, rest 2 min\n…" : "What do you want to do, and when?").foregroundStyle(Theme.dim), axis: .vertical)
                .lineLimit(5...12).coachInput()
            HStack(spacing: 10) {
                PhotosPicker(selection: $pick, matching: .images) {
                    Label(photo == nil ? "Add a photo" : "Change photo", systemImage: "photo")
                }
                .buttonStyle(OutlineButtonStyle())
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    Button("Remove") { self.photo = nil; pick = nil }.font(Theme.body(13.5)).foregroundStyle(Theme.muted)
                }
            }
            Text("The photo is only sent to the coach to read — it isn't stored.").font(Theme.meta(12)).foregroundStyle(Theme.dim)
            if !error.isEmpty { ErrorBox(text: error) }
            Button(busy ? "The coach is reading it…" : "Build my workouts") { Task { await build() } }
                .buttonStyle(BigButtonStyle())
                .disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil))
                .opacity(busy ? 0.6 : 1)
        }
        .onChange(of: pick) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                photo = img
            }
        }
    }

    /// ≤1600px JPEG — only sent to Gemini to read, never stored.
    private func jpeg(_ img: UIImage) -> Data? {
        let scale = min(1, 1600 / max(img.size.width, img.size.height))
        let size = CGSize(width: (img.size.width * scale).rounded(), height: (img.size.height * scale).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.85)
    }

    private func build() async {
        busy = true
        error = ""
        do {
            var res = try await Gemini.buildWorkouts(text: text, imageJPEG: photo.flatMap(jpeg), source: source, history: history)
            res.workouts = res.workouts.map { var w = $0; w.source = source; w.trainer = source == "trainer" ? trainer : ""; return w }
            onBuilt(res)
        } catch {
            self.error = error.localizedDescription.isEmpty ? "The coach couldn't build that — try again." : error.localizedDescription
        }
        busy = false
    }
}
