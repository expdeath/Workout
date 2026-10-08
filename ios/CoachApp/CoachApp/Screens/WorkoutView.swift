import SwiftUI
import PhotosUI
import AVKit
import AudioToolbox
import UserNotifications

/// Ports src/screens/Workout.jsx — the guided session: set logging
/// (strength kg×reps · cardio min/km · tick-off), rest timer, superset
/// flow, plate math, last-time hints, cue notes + form photo/clip, the
/// per-exercise ⋯ menu and "make it harder". Every edit goes through
/// AppState (persistToday → Firestore), exactly like the web app.
struct WorkoutView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    /// per-exercise ⋯ menu: which exercise, which page of the sheet
    struct SheetState: Identifiable {
        var exI: Int
        var mode: Mode
        enum Mode { case menu, swap, remove }
        var id: Int { exI }
    }

    struct HarderState {
        var loading = false
        var caution: String?
        var options: [Gemini.IntensifyOption] = []
        var applied: Set<Int> = []
        var error: String?
    }

    struct RestTimer: Equatable {
        var endsAt: Date
        var total: Double
        var exName: String
    }

    @State private var sheet: SheetState?
    @State private var swapDraft = ""
    @State private var confirmCancel: String? // "top" | "bottom"
    @State private var platesFor: Int?
    @State private var editingCue: Int?
    @State private var cueDraft = ""
    @State private var harder: HarderState?
    @State private var timer: RestTimer?
    @State private var restTask: Task<Void, Never>?
    @State private var mediaVersion = 0 // bump to re-read thumbnails
    @State private var viewer: MediaStore.Item?
    @State private var pickFor: String? // exercise name awaiting a photo/clip
    @State private var pickedItem: PhotosPickerItem?

    private static let efforts = ["", "easy", "good", "grind"]

    var body: some View {
        if let t = appState.todayPlan {
            content(t)
        } else {
            Color.clear.coachScreen().onAppear { appState.screen = .home }
        }
    }

    // MARK: - Layout

    private func content(_ t: Session) -> some View {
        let p = t.plan
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(t)
                if confirmCancel == "top" { cancelConfirm(t).padding(.top, 10) }

                Text(p.sessionType.uppercased())
                    .font(Theme.head(40, weight: .bold)).foregroundStyle(Theme.amber)
                    .padding(.top, 4)
                Text([p.title, p.estTimeMin > 0 ? "~\(p.estTimeMin) min" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.body(15)).foregroundStyle(Theme.muted)

                ReadinessBar(value: p.recoveryScore ?? 50, label: "Recovery").padding(.top, 14)

                // why + warm-up in one quiet card; the reasoning folds to 2 lines
                card {
                    if !p.reasoning.isEmpty { ExpandableText(text: p.reasoning, lines: 2) }
                    if !p.concerns.isEmpty {
                        Label(p.concerns, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.body(14)).foregroundStyle(Theme.amber)
                    }
                    if !p.warmup.isEmpty {
                        (Text("Warm-up  ").font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.muted)
                         + Text(p.warmup.joined(separator: " · ")).font(Theme.body(14)).foregroundStyle(Theme.textBody))
                            .padding(.top, p.reasoning.isEmpty ? 0 : 4)
                    }
                }
                .padding(.top, 4)

                exerciseCards(t)

                if let c = p.cardio, !(c.desc.isEmpty && c.duration.isEmpty) {
                    card {
                        label("Cardio")
                        Text([c.desc, c.duration].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.body(14.5))
                    }
                }
                if !p.cooldown.isEmpty {
                    card {
                        label("Cool-down")
                        Text(p.cooldown.joined(separator: " · ")).font(Theme.body(14.5))
                    }
                }

                harderSection(t)

                Button("Finish session") {
                    appState.fin = FinishInfo()
                    appState.screen = .finish
                }
                .buttonStyle(BigButtonStyle())
                .padding(.top, 18)

                Spacer().frame(height: timer == nil ? 24 : 96)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
        .overlay(alignment: .bottom) { restBar }
        .sheet(item: $sheet) { s in actionSheet(s, t) }
        .fullScreenCover(item: Binding(get: { viewer.map { ViewerItem(item: $0) } }, set: { viewer = $0?.item })) { v in
            mediaViewer(v.item)
        }
        .photosPicker(isPresented: Binding(get: { pickFor != nil }, set: { if !$0 { pickFor = nil } }),
                      selection: $pickedItem, matching: .any(of: [.images, .videos]))
        .onChange(of: pickedItem) { _, item in
            guard let item, let name = pickFor else { return }
            Task { await savePicked(item, for: name) }
        }
        .onDisappear { stopTimer() }
    }

    private func header(_ t: Session) -> some View {
        let total = t.log.reduce(0) { $0 + $1.count }
        let done = t.log.reduce(0) { $0 + $1.filter(\.done).count }
        return HStack(spacing: 0) {
            BackButton(label: "Home") { appState.screen = .home }
            Spacer()
            Text("\(done)/\(total) sets").font(Theme.meta(14, weight: .medium))
                .foregroundStyle(done == total && total > 0 ? Theme.teal : Theme.muted)
            Spacer()
            IconButton(icon: "bubble.left", label: "Ask the coach") { appState.chatOpen = true }
            IconButton(icon: "xmark", label: "Cancel this session") {
                confirmCancel = confirmCancel == "top" ? nil : "top"
            }
        }
    }

    private func cancelConfirm(_ t: Session) -> some View {
        let anyLogged = t.log.contains { $0.contains(where: \.isLogged) }
        return HStack(spacing: 10) {
            Text("Discard this session entirely?\(anyLogged ? " Your logged sets will be lost." : "")")
                .font(Theme.body(13.5)).foregroundStyle(Theme.textBody)
            Spacer(minLength: 4)
            Button("Discard") { stopTimer(); appState.cancelSession() }
                .font(Theme.head(14, weight: .bold)).foregroundStyle(Theme.red)
            Button("Keep") { confirmCancel = nil }
                .font(Theme.head(14, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Theme.redBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }

    // MARK: - Exercises

    /// Per-exercise context: logging mode, last time, suggestion, plate target.
    private struct ExMeta {
        var ex: Plan.Exercise
        var exI: Int
        var mode: String
        var lastPerf: Stats.LastPerformance?
        var suggest: Double?
        var plateTarget: Double?
    }

    private func exMeta(_ t: Session, _ exI: Int) -> ExMeta {
        let ex = t.plan.exercises[exI]
        let mode = Stats.logMode(ex.name, t.plan.sessionType)
        let lastPerf = Stats.lastPerformance(appState.history, ex.name)
        let suggest = mode != "strength" ? nil : Stats.suggestNextWeight(lastPerf, ex.reps)
        let typed = t.log[safe: exI]?.reversed().compactMap { Double($0.weight) }.first { $0 > 0 }
        let plateTarget = mode != "strength" ? nil : (typed ?? suggest ?? leadingNumber(ex.suggestedWeight))
        return ExMeta(ex: ex, exI: exI, mode: mode, lastPerf: lastPerf, suggest: suggest, plateTarget: plateTarget)
    }

    /// parseFloat("24kg") → 24, like JS.
    private func leadingNumber(_ s: String) -> Double? {
        guard let g = Stats.firstMatch(#"^\s*(\d+(?:\.\d+)?)"#, in: s), let n = g[safe: 1] ?? nil else { return nil }
        return Double(n)
    }

    /// Superset flow: two exercises sharing a letter merge into one card
    /// with rows interleaved A1 B1 A2 B2 — tick straight down.
    @ViewBuilder
    private func exerciseCards(_ t: Session) -> some View {
        let groups = groupedExercises(t.plan.exercises)
        ForEach(groups, id: \.self) { g in
            if g.count == 2 {
                let a = exMeta(t, g[0]), b = exMeta(t, g[1])
                exCard {
                    Text("Superset \(a.ex.superset)")
                        .font(Theme.meta(12.5, weight: .semibold)).foregroundStyle(Theme.teal).padding(.bottom, 6)
                    exHeader(a, dot: Theme.teal, paired: true)
                    Spacer().frame(height: 12)
                    exHeader(b, dot: Theme.amber, paired: true)
                    let rounds = max(t.log[safe: a.exI]?.count ?? 0, t.log[safe: b.exI]?.count ?? 0)
                    VStack(spacing: 8) {
                        ForEach(0..<rounds, id: \.self) { r in
                            setRow(t, a, r, dot: Theme.teal)
                            setRow(t, b, r, dot: Theme.amber)
                        }
                    }
                    .padding(.top, 10)
                }
            } else {
                let m = exMeta(t, g[0])
                exCard {
                    exHeader(m, dot: nil, paired: false)
                    VStack(spacing: 8) {
                        ForEach(0..<(t.log[safe: m.exI]?.count ?? 0), id: \.self) { setRow(t, m, $0, dot: nil) }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    /// [[i]] or [[i, partner]] in plan order — like the web's renderedIdx walk.
    private func groupedExercises(_ exs: [Plan.Exercise]) -> [[Int]] {
        var seen = Set<Int>(), out: [[Int]] = []
        for (i, ex) in exs.enumerated() where !seen.contains(i) {
            let partner = ex.superset.isEmpty ? nil
                : exs.indices.first { $0 != i && exs[$0].superset == ex.superset }
            if let partner, partner > i {
                seen.formUnion([i, partner]); out.append([i, partner])
            } else {
                seen.insert(i); out.append([i])
            }
        }
        return out
    }

    private func exHeader(_ m: ExMeta, dot: Color?, paired: Bool) -> some View {
        let ex = m.ex
        let key = cueKey(ex.name)
        let cue = LocalStore.shared.backup.aiSettings.cueNotes[key]
        let media = mediaVersion >= 0 ? MediaStore.get(key) : nil
        let tryWeight = m.suggest.map { "\(Helpers.fmtKg($0))kg" } ?? (m.mode == "strength" && !ex.suggestedWeight.isEmpty ? ex.suggestedWeight : nil)
        // one line of prescription, one line of guidance — everything else is in ⋯
        let prescription = ["\(ex.sets) × \(ex.reps)", ex.rpe.isEmpty ? "" : "RPE \(ex.rpe)", ex.rest.isEmpty ? "" : "\(ex.rest) rest"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(ex.name).font(Theme.head(20, weight: .bold))
                Spacer()
                Button { sheet = SheetState(exI: m.exI, mode: .menu) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 24)
                }
                .accessibilityLabel("Options for \(ex.name)")
            }
            Text(prescription).font(Theme.meta(13.5)).foregroundStyle(Theme.textBody)
            if tryWeight != nil || m.lastPerf != nil {
                HStack(spacing: 8) {
                    if let tryWeight {
                        Text("Try \(tryWeight)\(m.suggest != nil && m.lastPerf != nil ? " ↑" : "")")
                            .font(Theme.meta(13, weight: .semibold)).foregroundStyle(Theme.amber)
                    }
                    if let lp = m.lastPerf {
                        Text("Last \(lp.sets.map(\.formatted).joined(separator: ", "))")
                            .font(Theme.meta(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    if let target = m.plateTarget {
                        Spacer(minLength: 0)
                        Button { platesFor = platesFor == m.exI ? nil : m.exI } label: {
                            Image(systemName: "scalemass").font(.system(size: 14))
                                .foregroundStyle(platesFor == m.exI ? Theme.amber : Theme.teal)
                        }
                        .accessibilityLabel("Plate breakdown for \(Helpers.fmtKg(target))kg")
                    }
                }
            }
            if platesFor == m.exI, let target = m.plateTarget { plateLine(target) }
            if !paired && !ex.superset.isEmpty {
                Text("Superset \(ex.superset)").font(Theme.meta(12.5, weight: .medium)).foregroundStyle(Theme.teal)
            }
            if !ex.notes.isEmpty {
                Text(ex.notes).font(Theme.body(13.5)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            if editingCue == m.exI {
                cueEditor(ex.name, hasMedia: media != nil)
            } else if let cue {
                Label(cue, systemImage: "pencil").font(Theme.body(13.5)).foregroundStyle(Theme.amber)
                    .onTapGesture { cueDraft = cue; editingCue = m.exI }
            }
            if let media, editingCue != m.exI {
                Button { viewer = media } label: { mediaThumb(media) }
                    .accessibilityLabel("Form reference for \(ex.name)")
            }
        }
    }

    private func plateLine(_ target: Double) -> some View {
        let gym = LocalStore.shared.backup.aiSettings
        let bar = gym.barKg ?? Helpers.defaultBarKg
        let plates = Helpers.parsePlates(gym.plates) ?? Helpers.defaultPlates
        guard let info = Helpers.plateBreakdown(target, barKg: bar, plates: plates) else { return Text("") }
        let kg = Helpers.fmtKg
        var s = info.perSide.isEmpty
            ? "\(kg(target))kg → bar only (\(kg(info.bar))kg\(target < info.bar ? " — lighter than the bar" : ""))"
            : "\(kg(target))kg → \(kg(info.bar))kg bar + \(info.perSide.map(kg).joined(separator: " + ")) per side"
        if !info.perSide.isEmpty && !info.exact { s += " · closest load \(kg(info.loaded))kg" }
        return Text(s).font(Theme.meta(13)).foregroundStyle(Theme.amber)
    }

    private func setRow(_ t: Session, _ m: ExMeta, _ setI: Int, dot: Color?) -> some View {
        let set = t.log[safe: m.exI]?[safe: setI] ?? SetLog()
        let last = m.lastPerf?.sets[safe: setI]
        let exists = t.log[safe: m.exI]?[safe: setI] != nil
        return HStack(spacing: 8) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Button { toggleSet(t, m.exI, setI, set) } label: {
                Text(set.done ? "✓" : "\(setI + 1)")
                    .font(Theme.meta(14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(set.done ? Theme.bg : Theme.text)
                    .background(set.done ? Theme.teal : Theme.bgPill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            }
            .accessibilityLabel(set.done ? "Set \(setI + 1) done" : "Set \(setI + 1)")
            switch m.mode {
            case "check":
                Text(m.ex.reps)
                    .font(Theme.body(13.5)).foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSet(t, m.exI, setI, set) }
            case "cardio":
                numField(set.time, last?.time.nonEmpty ?? "min") { appState.updateSet(m.exI, setI, time: $0) }
                Text("min").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                numField(set.dist, last?.dist.nonEmpty ?? "km") { appState.updateSet(m.exI, setI, dist: $0) }
                Text("km").font(Theme.meta(13)).foregroundStyle(Theme.muted)
            default:
                numField(set.weight, m.suggest.map(Helpers.fmtKg) ?? last?.weight.nonEmpty ?? "kg") { appState.updateSet(m.exI, setI, weight: $0) }
                Text("×").font(Theme.meta(13)).foregroundStyle(Theme.muted)
                numField(set.reps, last?.reps.nonEmpty ?? "reps", decimal: false) { appState.updateSet(m.exI, setI, reps: $0) }
            }
            if m.mode != "check" {
                // the effort tag only appears once the set is ticked — no
                // "rate" on every untouched row (its space stays reserved)
                let showEffort = set.done || !set.effort.isEmpty
                Button(set.effort.isEmpty ? "rate" : set.effort) {
                    let i = Self.efforts.firstIndex(of: set.effort) ?? 0
                    appState.updateSet(m.exI, setI, effort: Self.efforts[(i + 1) % Self.efforts.count])
                }
                .font(Theme.meta(12.5, weight: .medium))
                .foregroundStyle(effortColor(set.effort))
                .frame(minWidth: 44)
                .opacity(showEffort ? 1 : 0)
                .disabled(!showEffort)
                .accessibilityHidden(!showEffort)
                .accessibilityLabel("Effort for set \(setI + 1): \(set.effort.isEmpty ? "not rated" : set.effort)")
            }
        }
        .opacity(exists ? 1 : 0)
    }

    private func effortColor(_ e: String) -> Color {
        switch e {
        case "easy": return Theme.teal
        case "good": return Theme.amber
        case "grind": return Theme.red
        default: return Theme.dim
        }
    }

    private func numField(_ value: String, _ placeholder: String, decimal: Bool = true, set: @escaping (String) -> Void) -> some View {
        TextField("", text: Binding(get: { value }, set: set), prompt: Text(placeholder).foregroundStyle(Theme.dim))
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(Theme.mono(15))
            .frame(maxWidth: 76)
            .padding(.vertical, 8)
            .background(Theme.bgInput)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(Theme.borderDim))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }

    // MARK: - Cue notes + form media

    private func cueKey(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    private func cueEditor(_ name: String, hasMedia: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $cueDraft, prompt: Text("Note to self, e.g. seat height 4").foregroundStyle(Theme.dim), axis: .vertical)
                .lineLimit(2...5)
                .coachInput()
            HStack(spacing: 8) {
                chip("Save", on: true) { saveCue(name) }
                chip(hasMedia ? "Replace photo" : "Add photo") { pickFor = name }
                if hasMedia { chip("Remove photo") { MediaStore.remove(cueKey(name)); mediaVersion += 1 } }
                chip("Cancel") { editingCue = nil }
            }
            Text("Photos stay on this device.")
                .font(Theme.meta(12)).foregroundStyle(Theme.dim)
        }
        .padding(.top, 6)
    }

    private func saveCue(_ name: String) {
        let text = String(cueDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let key = cueKey(name)
        LocalStore.shared.updateAISettings { s in
            if text.isEmpty { s.cueNotes[key] = nil } else { s.cueNotes[key] = text }
        }
        editingCue = nil
    }

    private func savePicked(_ item: PhotosPickerItem, for name: String) async {
        defer { pickedItem = nil; pickFor = nil }
        let key = cueKey(name)
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
           let movie = try? await item.loadTransferable(type: PickedMovie.self) {
            try? MediaStore.put(key, movieAt: movie.url)
            try? FileManager.default.removeItem(at: movie.url)
        } else if let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) {
            try? MediaStore.put(key, imageData: jpg)
        }
        mediaVersion += 1
    }

    private func mediaThumb(_ m: MediaStore.Item) -> some View {
        ZStack {
            if !m.isVideo, let img = UIImage(contentsOfFile: m.url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.bgPill
            }
            Text(m.isVideo ? "▶" : "🔍").font(.system(size: 20)).foregroundStyle(.white)
        }
        .frame(width: 96, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        .padding(.top, 6)
    }

    private struct ViewerItem: Identifiable { let item: MediaStore.Item; var id: URL { item.url } }

    private func mediaViewer(_ m: MediaStore.Item) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if m.isVideo {
                VideoPlayer(player: AVPlayer(url: m.url))
            } else if let img = UIImage(contentsOfFile: m.url.path) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button("✕") { viewer = nil }
                .font(Theme.head(22, weight: .bold)).foregroundStyle(.white).padding(20)
        }
    }

    // MARK: - ⋯ menu (bottom sheet)

    @ViewBuilder
    private func actionSheet(_ s: SheetState, _ t: Session) -> some View {
        let ex = t.plan.exercises[safe: s.exI]
        let rows = t.log[safe: s.exI] ?? []
        let canDrop = rows.count > 1 && !(rows.last?.isLogged ?? true)
        VStack(alignment: .leading, spacing: 4) {
            Text(ex?.name ?? "").font(Theme.head(20, weight: .bold)).padding(.bottom, 8)
            switch s.mode {
            case .menu:
                if let ex, !ex.alt.isEmpty {
                    sheetItem("Swap to \(ex.alt)", icon: "arrow.left.arrow.right", color: Theme.teal) { sheet = nil; appState.swapExercise(s.exI) }
                }
                sheetItem("Did something else…", icon: "pencil.line", color: Theme.teal) { swapDraft = ""; sheet = SheetState(exI: s.exI, mode: .swap) }
                sheetItem("How-to video", icon: "play.rectangle") {
                    sheet = nil
                    let q = "how to \(ex?.name ?? "") proper form".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://www.youtube.com/results?search_query=\(q)") { openURL(url) }
                }
                sheetItem("Add set", icon: "plus") { sheet = nil; appState.adjustSets(s.exI, +1) }
                sheetItem("Remove set", icon: "minus", enabled: canDrop) { sheet = nil; appState.adjustSets(s.exI, -1) }
                let cue = LocalStore.shared.backup.aiSettings.cueNotes[cueKey(ex?.name ?? "")]
                sheetItem(cue == nil ? "Note or photo" : "Edit note", icon: "note.text") {
                    cueDraft = cue ?? ""; editingCue = s.exI; sheet = nil
                }
                sheetItem("Remove exercise", icon: "trash", color: Theme.red) { sheet = SheetState(exI: s.exI, mode: .remove) }
            case .swap:
                Text("What did you do instead?")
                    .font(Theme.body(14)).foregroundStyle(Theme.muted)
                TextField("", text: Binding(get: { swapDraft }, set: { swapDraft = String($0.prefix(60)) }),
                          prompt: Text("e.g. Running").foregroundStyle(Theme.dim))
                    .coachInput()
                    .onSubmit { saveSwap(s.exI) }
                Button("Swap it in") { saveSwap(s.exI) }
                    .buttonStyle(BigButtonStyle())
                    .disabled(swapDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
            case .remove:
                Text("Skip it today?\(rows.contains(where: \.isLogged) ? " Logged sets will be lost." : "")")
                    .font(Theme.body(14)).foregroundStyle(Theme.muted)
                Button("Remove exercise") { sheet = nil; appState.removeExercise(s.exI) }
                    .buttonStyle(BigButtonStyle(danger: true))
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachScreen()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func saveSwap(_ exI: Int) {
        let name = swapDraft.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { appState.renameExercise(exI, name) }
        sheet = nil
    }

    private func sheetItem(_ title: String, icon: String, color: Color = Theme.text, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: icon).frame(width: 24) }
                .font(Theme.body(16)).foregroundStyle(enabled ? color : Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Make it harder

    @ViewBuilder
    private func harderSection(_ t: Session) -> some View {
        if let h = harder {
            card {
                HStack {
                    label("Push harder")
                    Spacer()
                    IconButton(icon: "xmark", label: "Close") { harder = nil }.frame(height: 24)
                }
                if let c = h.caution { Text(c).font(Theme.body(13.5)).foregroundStyle(Theme.amber) }
                if h.loading { Text("Picking upgrades…").font(Theme.body(14)).foregroundStyle(Theme.muted) }
                if let e = h.error { Text(e).font(Theme.body(14)).foregroundStyle(Theme.amber) }
                ForEach(Array(h.options.enumerated()), id: \.offset) { i, o in
                    let applied = h.applied.contains(i)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(harderLabel(o)).font(Theme.body(14.5))
                            if !o.why.isEmpty { Text(o.why).font(Theme.meta(12)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        Button(applied ? "✓ In" : "Apply") {
                            if appState.applyHarder(o) { harder?.applied.insert(i) }
                        }
                        .font(Theme.head(14, weight: .bold))
                        .foregroundStyle(applied ? Theme.muted : Theme.teal)
                        .disabled(applied)
                    }
                    .padding(.top, 6)
                }
                if !h.loading && h.error == nil && h.options.isEmpty {
                    Text("Nothing to add today — finish strong.").font(Theme.body(14)).foregroundStyle(Theme.muted)
                }
            }
        } else {
            Button("Make it harder") { Task { await openHarder(t) } }
                .font(Theme.head(15, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5])))
                .padding(.top, 14)
        }
    }

    private func openHarder(_ t: Session) async {
        let health = LocalStore.shared.backup.health
        // gentle data-driven reminder, shown instantly while the AI thinks
        let caution = Stats.recoveryCaution(t.checkin, appState.history, health)
        harder = HarderState(loading: true, caution: caution)
        do {
            let res = try await Gemini.intensifyWorkout(today: t, history: appState.history, healthLog: health)
            harder = HarderState(caution: caution ?? (res.note.isEmpty ? nil : res.note), options: res.options)
        } catch {
            harder = HarderState(caution: caution, error: "Couldn’t reach the coach — try again in a moment.")
        }
    }

    private func harderLabel(_ o: Gemini.IntensifyOption) -> String {
        let w = { (ex: Plan.Exercise) in ex.suggestedWeight.isEmpty ? "" : " @ \(ex.suggestedWeight)" }
        switch o.kind {
        case "add": return o.exercise.map { "Add \($0.name) — \($0.sets)×\($0.reps)\(w($0))" } ?? "Add an exercise"
        case "extraSet": return "One more set of \(o.target)"
        default: return o.exercise.map { "Swap \(o.target) → \($0.name) — \($0.sets)×\($0.reps)\(w($0))" } ?? "Swap \(o.target)"
        }
    }

    // MARK: - Rest timer

    /// "90s" → 90 · "2min" → 120 · "1-2min" → 120 · fallback 90 (parseRestSeconds).
    static func parseRestSeconds(_ rest: String) -> Double {
        guard let g = Stats.firstMatch(#"(\d+)(?:\s*-\s*(\d+))?\s*(s|sec|m|min)?"#, in: rest),
              let first = g[safe: 1] ?? nil, let n = Double((g[safe: 2] ?? nil) ?? first) else { return 90 }
        let unit = ((g[safe: 3] ?? nil) ?? "s").lowercased()
        let secs = unit.hasPrefix("m") ? n * 60 : n
        return min(max(secs, 15), 600)
    }

    private func toggleSet(_ t: Session, _ exI: Int, _ setI: Int, _ set: SetLog) {
        let turningOn = !set.done
        appState.updateSet(exI, setI, done: turningOn)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard turningOn, let ex = t.plan.exercises[safe: exI] else { return }
        startTimer(seconds: Self.parseRestSeconds(ex.rest), exName: ex.name)
    }

    private func startTimer(seconds: Double, exName: String) {
        stopTimer()
        let rest = RestTimer(endsAt: Date().addingTimeInterval(seconds), total: seconds, exName: exName)
        timer = rest
        UIApplication.shared.isIdleTimerDisabled = true // screen stays on while resting
        // a real notification: fires even with the phone locked or in another app
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "⏱ Rest over — GO"
            content.body = "Next set: \(exName)"
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "rest-timer", content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
        }
        restTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1005)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            timer = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func stopTimer() {
        restTask?.cancel()
        restTask = nil
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
    }

    @ViewBuilder
    private var restBar: some View {
        if let timer {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let remaining = Int(ceil(timer.endsAt.timeIntervalSince(ctx.date)))
                let frac = max(0, min(1, Double(remaining) / timer.total))
                ZStack(alignment: .leading) {
                    GeometryReader { geo in
                        (remaining <= 0 ? Theme.teal : Theme.amber).opacity(0.25)
                            .frame(width: geo.size.width * frac)
                    }
                    HStack {
                        Text(remaining <= 0 ? "GO" : String(format: "%d:%02d", max(remaining, 0) / 60, max(remaining, 0) % 60))
                            .font(Theme.mono(22, weight: .medium))
                            .foregroundStyle(remaining <= 0 ? Theme.teal : Theme.text)
                        Text(remaining <= 0 ? "Next set · \(timer.exName)" : timer.exName)
                            .font(Theme.body(14)).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer()
                        Button("Skip") { stopTimer() }
                            .font(Theme.head(15, weight: .semibold)).textCase(.uppercase).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(height: 64)
                .background(Theme.bgCard)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
            }
            .accessibilityIdentifier("rest-bar")
        }
    }

    // MARK: - Small pieces

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 12)
    }

    private func exCard(@ViewBuilder _ content: () -> some View) -> some View {
        card(content)
    }

    private func label(_ s: String) -> some View {
        CardLabel(text: s)
    }

    private func chip(_ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.body(13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Theme.bg : Theme.text)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(on ? Theme.teal : Theme.bgPill)
            .clipShape(Capsule())
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
