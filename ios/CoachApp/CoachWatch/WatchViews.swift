import SwiftUI
import WatchKit

// MARK: - Look (the iPhone app's Theme, for the wrist)

enum W {
    static let bg = Color.black
    static let card = Color(red: 0x13 / 255, green: 0x1B / 255, blue: 0x2E / 255)
    static let pill = Color(red: 0x1A / 255, green: 0x1F / 255, blue: 0x2B / 255)
    static let text = Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255)
    static let muted = Color(red: 0x83 / 255, green: 0x91 / 255, blue: 0xA7 / 255)
    static let dim = Color(red: 0x4E / 255, green: 0x58 / 255, blue: 0x69 / 255)
    static let amber = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let green = Color(red: 0x56 / 255, green: 0xE5 / 255, blue: 0xA9 / 255)
    static let red = Color(red: 0xF2 / 255, green: 0x6D / 255, blue: 0x5B / 255)

    static func num(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Bold", size: size) }
    static func head(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(weight == .bold ? "SpaceGrotesk-Bold" : "SpaceGrotesk-Medium", size: size)
    }
}

private enum Page { case set, list, finish }

/// A set just logged here — its effort can be tapped in during the rest.
private struct Logged: Equatable { var ex: Int; var set: Int; var name: String }

struct WatchRoot: View {
    @State private var page = Page.set
    @State private var picked: Int? // exercise chosen from the list; nil = follow the plan
    @State private var logged: Logged?

    var body: some View {
        let link = PhoneLink.shared
        let s = link.state
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let now = Int64(ctx.date.timeIntervalSince1970 * 1000)
            let rest = s.rest.flatMap { now < $0.endsAt + 4_000 ? $0 : nil }
            Group {
                if !s.active && s.finished {
                    DoneView(state: s)
                } else if !s.active {
                    IdleView(reachable: link.reachable)
                } else if page == .list {
                    ListPage(state: s, now: now, onPick: { picked = $0; page = .set }, onFinish: { page = .finish }, onBack: { page = .set })
                } else if page == .finish {
                    FinishPage(onSave: { link.send(WatchCommand.finish, rpe: $0) }, onBack: { page = .list })
                } else if let rest {
                    RestPage(state: s, rest: rest, now: now, logged: logged)
                } else {
                    SetPage(state: s, now: now, picked: picked,
                            onList: { page = .list },
                            onLogged: { l, finishedExercise in logged = l; if finishedExercise { picked = nil } },
                            onNext: { picked = nil })
                }
            }
        }
        .onChange(of: s.active) { _, active in
            if !active { page = .set; picked = nil; logged = nil }
        }
    }
}

// MARK: - Top line: heart rate · elapsed · sets

private struct TopLine: View {
    let state: WatchState
    let now: Int64

    var body: some View {
        let mins = state.startedAt > 0 ? max(0, (now - state.startedAt) / 60_000) : 0
        HStack(spacing: 7) {
            if let hr = WorkoutManager.shared.heartRate {
                Text("♥ \(hr)").font(W.num(15)).foregroundStyle(W.red)
            }
            Text(mins >= 60 ? "\(mins / 60)h\(String(format: "%02d", mins % 60))" : "\(mins)m").font(W.num(15)).foregroundStyle(W.muted)
            Text("\(state.doneSets)/\(state.totalSets)").font(W.num(15))
                .foregroundStyle(state.doneSets == state.totalSets ? W.green : W.muted)
        }
    }
}

// MARK: - Set

private struct SetPage: View {
    let state: WatchState
    let now: Int64
    let picked: Int?
    let onList: () -> Void
    let onLogged: (Logged, Bool) -> Void
    let onNext: () -> Void

    var body: some View {
        let exI = picked.flatMap { state.exercises.indices.contains($0) ? $0 : nil } ?? state.next()?.ex
        if let exI {
            let ex = state.exercises[exI]
            if let setI = state.nextSet(exI) {
                SetEditor(state: state, now: now, exI: exI, setI: setI, onList: onList, onLogged: onLogged)
                    .id("\(state.id)/\(exI)/\(setI)") // fresh dials for each set
            } else {
                VStack(spacing: 8) {
                    TopLine(state: state, now: now)
                    Button(action: onList) { Text(ex.name).font(W.head(16)).multilineTextAlignment(.center).lineLimit(2) }.buttonStyle(.plain)
                    Text("\(ex.sets.count)/\(ex.sets.count) sets ✓").font(W.num(17)).foregroundStyle(W.green)
                    HStack(spacing: 8) {
                        Pill("+ Set", W.pill, W.text) { PhoneLink.shared.send(WatchCommand.addSet, ex: exI, name: ex.name) }
                        Pill("Next", W.green, W.bg, action: onNext)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                TopLine(state: state, now: now)
                Text("All sets done").font(W.head(17)).foregroundStyle(W.green)
                Pill("Finish workout", W.green, W.bg, action: onList)
            }
        }
    }
}

private struct SetEditor: View {
    let state: WatchState
    let now: Int64
    let exI: Int
    let setI: Int
    let onList: () -> Void
    let onLogged: (Logged, Bool) -> Void

    @State private var a = ""
    @State private var b = ""
    @State private var sel = 0
    @State private var crown = 0.0
    @State private var crownSteps = 0
    @FocusState private var focused: Bool

    private var ex: WExercise { state.exercises[exI] }
    private var cardio: Bool { ex.mode == "cardio" }

    var body: some View {
        VStack(spacing: 3) {
            TopLine(state: state, now: now)
            Button(action: onList) {
                Text(ex.name).font(W.head(15)).foregroundStyle(W.text).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows all exercises")
            let partner = ex.superset.isEmpty ? "" : " · \(ex.superset)\(setI + 1)"
            Text("SET \(setI + 1) OF \(ex.sets.count)\(partner)").font(W.head(11, .medium)).foregroundStyle(W.amber)

            if ex.mode != "check" {
                HStack(spacing: 3) {
                    Round("−", "Less") { bump(-1) }
                    Dial(value: a, unit: cardio ? "min" : "kg", selected: sel == 0) { sel = 0 }
                    Dial(value: b, unit: cardio ? "km" : "reps", selected: sel == 1) { sel = 1 }
                    Round("+", "More") { bump(1) }
                }
                .focusable()
                .focused($focused)
                .digitalCrownRotation($crown, from: -10_000, through: 10_000, by: 1, sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
                .onChange(of: crown) { _, v in
                    // one step per crown detent
                    let steps = Int(v.rounded())
                    let d = steps - crownSteps
                    crownSteps = steps
                    if d != 0 { bump(d > 0 ? 1 : -1, haptic: false) }
                }
                if !ex.last.isEmpty {
                    Text("Last \(ex.last)").font(W.head(10, .medium)).foregroundStyle(W.muted).lineLimit(1)
                }
            } else {
                Text(ex.reps).font(W.head(13, .medium)).foregroundStyle(W.muted).multilineTextAlignment(.center).lineLimit(2)
            }

            Pill("DONE", W.green, W.bg, tall: true) { done() }
                .padding(.top, 2)
        }
        .onAppear {
            let p = state.prefill(exI, setI)
            a = cardio ? p.t : p.w
            b = cardio ? p.d : p.r
            focused = true
        }
    }

    /// − / + and the crown change whichever dial is selected.
    private func bump(_ dir: Int, haptic: Bool = true) {
        if sel == 0 { a = step(a, Double(dir) * (cardio ? 1 : weightStep(a)), decimals: cardio ? 0 : 1) }
        else { b = step(b, Double(dir) * (cardio ? 0.1 : 1), decimals: cardio ? 1 : 0) }
        if haptic { WKInterfaceDevice.current().play(.click) }
    }

    private func done() {
        WKInterfaceDevice.current().play(.success)
        let link = PhoneLink.shared
        switch ex.mode {
        case "cardio": link.send(WatchCommand.logSet, ex: exI, name: ex.name, set: setI, t: a, d: b)
        case "check": link.send(WatchCommand.logSet, ex: exI, name: ex.name, set: setI)
        default: link.send(WatchCommand.logSet, ex: exI, name: ex.name, set: setI, w: a, r: b)
        }
        let finishedExercise = ex.sets.enumerated().allSatisfy { j, x in x.done || j == setI }
        onLogged(Logged(ex: exI, set: setI, name: ex.name), finishedExercise)
    }
}

/// Plates move in 2.5s on a bar, dumbbells in 1s up to 20.
private func weightStep(_ v: String) -> Double { (Double(v) ?? 0) < 20 ? 1 : 2.5 }

private func step(_ v: String, _ by: Double, decimals: Int) -> String {
    let n = max((Double(v) ?? 0) + by, 0)
    let r = decimals == 0 ? n.rounded() : (n * 10).rounded() / 10
    if r == 0 && by < 0 { return "" }
    return r == r.rounded() ? String(Int(r)) : String(r)
}

private struct Dial: View {
    let value: String
    let unit: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: -2) {
                Text(value.isEmpty ? "–" : value).font(W.num(24)).foregroundStyle(selected ? W.text : W.muted).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(W.head(9, .medium)).foregroundStyle(W.muted)
            }
            .frame(width: 50, height: 44)
            .background(W.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? W.amber : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(unit)")
        .accessibilityHint(selected ? "Turn the Digital Crown to change" : "Select, then turn the Digital Crown")
    }
}

private struct Round: View {
    let label: String
    let desc: String
    let action: () -> Void
    init(_ label: String, _ desc: String, action: @escaping () -> Void) { self.label = label; self.desc = desc; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(label).font(W.num(20)).foregroundStyle(W.text).frame(width: 26, height: 26).background(W.pill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(desc)
    }
}

private struct Pill: View {
    let label: String
    let bg: Color
    let fg: Color
    var tall = false
    let action: () -> Void
    init(_ label: String, _ bg: Color, _ fg: Color, tall: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.bg = bg; self.fg = fg; self.tall = tall; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label).font(W.head(tall ? 16 : 13)).foregroundStyle(fg).lineLimit(1)
                .padding(.horizontal, 12).frame(maxWidth: tall ? .infinity : nil, minHeight: tall ? 38 : 30)
                .background(bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rest

private struct RestPage: View {
    let state: WatchState
    let rest: WRest
    let now: Int64
    let logged: Logged?

    var body: some View {
        let left = Int(ceil(Double(rest.endsAt - now) / 1000))
        let over = left <= 0
        let frac = rest.total > 0 ? min(max(Double(left) / Double(rest.total), 0), 1) : 0
        let next = state.next().flatMap { f in state.exercises.indices.contains(f.ex) ? "\(state.exercises[f.ex].name) · set \(f.set + 1)" : nil }
        // effort for the set just logged here (the iPhone shows the same tag)
        let ratable: WSet? = logged.flatMap { l in
            guard state.exercises.indices.contains(l.ex) else { return nil }
            let e = state.exercises[l.ex]
            guard e.name == l.name, e.mode != "check", e.sets.indices.contains(l.set) else { return nil }
            return e.sets[l.set]
        }
        ZStack {
            Circle().stroke(W.pill, lineWidth: 5)
            Circle().trim(from: 0, to: frac).stroke(over ? W.green : W.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                Text(over ? "GO" : "REST").font(W.head(11, .medium)).foregroundStyle(over ? W.green : W.muted)
                Text(over ? "GO" : String(format: "%d:%02d", max(left, 0) / 60, max(left, 0) % 60))
                    .font(W.num(40)).foregroundStyle(over ? W.green : W.text)
                    .accessibilityLabel(over ? "Rest over" : "\(left) seconds of rest left")
                if let next { Text("Next: \(next)").font(W.head(10, .medium)).foregroundStyle(W.muted).lineLimit(1) }
                if let ratable, let logged {
                    HStack(spacing: 3) {
                        ForEach([("easy", W.green), ("good", W.amber), ("grind", W.red)], id: \.0) { e, c in
                            let on = ratable.e == e
                            Button {
                                PhoneLink.shared.send(WatchCommand.effort, ex: logged.ex, name: logged.name, set: logged.set, effort: on ? "" : e)
                            } label: {
                                Text(e).font(W.head(10, .medium)).foregroundStyle(on ? W.bg : c)
                                    .padding(.horizontal, 6).padding(.vertical, 4).background(on ? c : W.pill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 6) {
                    if !over { Pill("+15s", W.pill, W.text) { PhoneLink.shared.send(WatchCommand.restAdd, sec: 15) } }
                    Pill(over ? "Next set" : "Skip", over ? W.green : W.pill, over ? W.bg : W.text) { PhoneLink.shared.send(WatchCommand.restSkip) }
                }
            }
            .padding(14)
        }
        .padding(2)
    }
}

// MARK: - All exercises + finish

private struct ListPage: View {
    let state: WatchState
    let now: Int64
    let onPick: (Int) -> Void
    let onFinish: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                TopLine(state: state, now: now)
                Text((state.title.isEmpty ? state.type : state.title).uppercased()).font(W.head(12)).foregroundStyle(W.amber).lineLimit(1)
                ForEach(Array(state.exercises.enumerated()), id: \.offset) { i, ex in
                    let done = !ex.sets.isEmpty && ex.doneSets == ex.sets.count
                    Button { onPick(i) } label: {
                        HStack {
                            Text(ex.name).font(W.head(13, .medium)).foregroundStyle(done ? W.muted : W.text).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Text(done ? "✓" : "\(ex.doneSets)/\(ex.sets.count)").font(W.num(16)).foregroundStyle(done ? W.green : W.muted)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(W.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Pill("Finish workout", W.amber, W.bg, tall: true, action: onFinish).padding(.top, 4)
                Pill("Back", W.pill, W.text, action: onBack)
            }
        }
    }
}

private struct FinishPage: View {
    let onSave: (Int) -> Void
    let onBack: () -> Void
    @State private var rpe = 7.0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text("HOW HARD?").font(W.head(11, .medium)).foregroundStyle(W.muted)
            HStack(spacing: 12) {
                Round("−", "Easier") { rpe = max(rpe - 1, 1) }
                Text("\(Int(rpe))").font(W.num(44)).foregroundStyle(W.amber).frame(minWidth: 40)
                    .accessibilityLabel("Session effort \(Int(rpe)) out of 10")
                Round("+", "Harder") { rpe = min(rpe + 1, 10) }
            }
            .focusable()
            .focused($focused)
            .digitalCrownRotation($rpe, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            Text(rpeLabel(Int(rpe))).font(W.head(11, .medium)).foregroundStyle(W.muted)
            Pill("Save workout", W.green, W.bg, tall: true) { onSave(Int(rpe)) }
            Pill("Back", W.pill, W.text, action: onBack)
        }
        .onAppear { focused = true }
    }

    private func rpeLabel(_ r: Int) -> String {
        switch r {
        case ...3: return "Easy"
        case ...5: return "Moderate"
        case ...7: return "Hard"
        case ...9: return "Very hard"
        default: return "All out"
        }
    }
}

// MARK: - No workout / just finished

private struct IdleView: View {
    let reachable: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("COACH").font(W.head(20)).foregroundStyle(W.amber)
            Text(reachable
                 ? "Start today's workout on your iPhone. Sets, rest and finish show up here."
                 : "iPhone not connected. Start your workout in COACH on your iPhone — it shows up here.")
                .font(W.head(13, .medium)).foregroundStyle(W.muted).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

private struct DoneView: View {
    let state: WatchState

    var body: some View {
        VStack(spacing: 6) {
            Text("✓").font(W.num(40)).foregroundStyle(W.green)
            Text("Workout saved").font(W.head(16))
            Text(state.title.isEmpty ? state.type : state.title).font(W.head(12, .medium)).foregroundStyle(W.muted).multilineTextAlignment(.center).lineLimit(2)
            Text("The details are on your iPhone.").font(W.head(11, .medium)).foregroundStyle(W.dim).multilineTextAlignment(.center)
        }
    }
}
