import Foundation

// The phone ↔ watch protocol — docs/watch.md is the spec, and
// android/watchlink/…/WatchLink.kt (android branch) is the same thing in
// Kotlin, so a COACH watch speaks the same JSON on either platform.
//
// The phone owns the workout: it sends a WatchState snapshot whenever
// today's session or the rest timer changes, and the watch sends back
// small WatchCommands ("set 2 done: 60 kg × 8"). The watch applies its own
// commands to the last snapshot straight away (`applying`), so the wrist
// never waits on Bluetooth; the phone's next snapshot lists the command
// ids it has applied (`acks`) and replaces the guess.
//
// Compiled into both the iPhone app and the watch app (project.yml).

nonisolated enum WatchPaths {
    static let version = 1
    /// WatchConnectivity keys: the JSON travels as a string under these.
    static let stateKey = "state"
    static let commandKey = "cmd"
}

/// One set as the watch sees it. w/r/t/d are what's logged (strings, like
/// SetLog); pw/pr/pt are the greyed hints the phone shows in an empty
/// field — the suggested weight, last time's reps/minutes.
nonisolated struct WSet: Equatable, Sendable {
    var w = "", r = "", t = "", d = ""
    var done = false
    var e = ""
    var pw = "", pr = "", pt = ""

    var json: [String: Any] { ["w": w, "r": r, "t": t, "d": d, "done": done, "e": e, "pw": pw, "pr": pr, "pt": pt] }

    init(w: String = "", r: String = "", t: String = "", d: String = "", done: Bool = false, e: String = "", pw: String = "", pr: String = "", pt: String = "") {
        self.w = w; self.r = r; self.t = t; self.d = d; self.done = done; self.e = e; self.pw = pw; self.pr = pr; self.pt = pt
    }

    init(json o: [String: Any]) {
        self.init(w: o.str("w"), r: o.str("r"), t: o.str("t"), d: o.str("d"), done: o.bool("done"), e: o.str("e"),
                  pw: o.str("pw"), pr: o.str("pr"), pt: o.str("pt"))
    }
}

/// mode: "strength" (kg × reps) · "cardio" (min / km) · "check" (tick only).
nonisolated struct WExercise: Equatable, Sendable {
    var name: String
    var mode = "strength"
    var reps = ""
    var rpe = ""
    var restSec = 90
    /// What to try today ("62.5").
    var target = ""
    /// Last time, formatted ("60kg×8, 60kg×8").
    var last = ""
    var superset = ""
    var sets: [WSet] = []

    var doneSets: Int { sets.filter(\.done).count }

    var json: [String: Any] {
        ["name": name, "mode": mode, "reps": reps, "rpe": rpe, "restSec": restSec, "target": target,
         "last": last, "superset": superset, "sets": sets.map(\.json)]
    }

    init(name: String, mode: String = "strength", reps: String = "", rpe: String = "", restSec: Int = 90,
         target: String = "", last: String = "", superset: String = "", sets: [WSet] = []) {
        self.name = name; self.mode = mode; self.reps = reps; self.rpe = rpe; self.restSec = restSec
        self.target = target; self.last = last; self.superset = superset; self.sets = sets
    }

    init(json o: [String: Any]) {
        let mode = o.str("mode")
        self.init(name: o.str("name"), mode: mode.isEmpty ? "strength" : mode, reps: o.str("reps"), rpe: o.str("rpe"),
                  restSec: o.int("restSec") ?? 90, target: o.str("target"), last: o.str("last"), superset: o.str("superset"),
                  sets: (o["sets"] as? [Any])?.compactMap { ($0 as? [String: Any]).map(WSet.init(json:)) } ?? [])
    }
}

/// The running rest timer. endsAt is epoch ms — both devices keep network time.
nonisolated struct WRest: Equatable, Sendable {
    var endsAt: Int64
    var total: Int
    var ex: String

    var json: [String: Any] { ["endsAt": endsAt, "total": total, "ex": ex] }

    init(endsAt: Int64, total: Int, ex: String) { self.endsAt = endsAt; self.total = total; self.ex = ex }

    init?(json o: [String: Any]) {
        guard let end = o.int64("endsAt") else { return nil }
        self.init(endsAt: end, total: o.int("total") ?? 90, ex: o.str("ex"))
    }
}

/// Where to go next: an exercise and a set in it.
nonisolated struct WFocus: Equatable, Sendable { var ex: Int; var set: Int }

/// What the watch pre-fills for a set: what's logged, else the set before
/// it today, else the phone's hint.
nonisolated struct WPrefill: Equatable, Sendable { var w: String; var r: String; var t: String; var d: String }

nonisolated struct WatchState: Equatable, Sendable {
    /// A workout is running on the phone (today's session, not finished).
    var active = false
    var id = ""
    var type = ""
    var title = ""
    var startedAt: Int64 = 0
    var exercises: [WExercise] = []
    var rest: WRest?
    /// The last command ids the phone applied.
    var acks: [String] = []
    /// The session was just finished (on either device) — the watch wraps up.
    var finished = false
    var sentAt: Int64 = 0

    var doneSets: Int { exercises.reduce(0) { $0 + $1.doneSets } }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// The web's superset flow: two exercises sharing a letter run as
    /// rounds A1 B1 A2 B2; everything else in plan order. The first set not
    /// done yet is next.
    func next() -> WFocus? {
        for g in Self.groups(exercises) {
            let rounds = g.map { exercises[$0].sets.count }.max() ?? 0
            for r in 0..<rounds {
                for i in g where r < exercises[i].sets.count && !exercises[i].sets[r].done {
                    return WFocus(ex: i, set: r)
                }
            }
        }
        return nil
    }

    /// The first set of this exercise not done yet (nil: all done).
    func nextSet(_ ex: Int) -> Int? {
        guard exercises.indices.contains(ex) else { return nil }
        return exercises[ex].sets.firstIndex { !$0.done }
    }

    func prefill(_ ex: Int, _ set: Int) -> WPrefill {
        guard exercises.indices.contains(ex) else { return WPrefill(w: "", r: "", t: "", d: "") }
        let e = exercises[ex]
        let s = e.sets.indices.contains(set) ? e.sets[set] : WSet()
        // the nearest earlier set logged today — the weight you just lifted
        let before = e.sets.prefix(min(max(set, 0), e.sets.count)).last { $0.done || !$0.w.isEmpty || !$0.r.isEmpty || !$0.t.isEmpty }
        func pick(_ v: String...) -> String { v.first { !$0.isEmpty } ?? "" }
        return WPrefill(
            w: pick(s.w, before?.w ?? "", s.pw, e.target),
            r: pick(s.r, before?.r ?? "", s.pr, Self.firstNumber(e.reps)),
            t: pick(s.t, before?.t ?? "", s.pt),
            d: pick(s.d, before?.d ?? "")
        )
    }

    /// Which exercise a command means: its index when the name still
    /// matches (the plan can change on the phone mid-workout), else the
    /// exercise with that name.
    func exerciseIndex(_ cmd: WatchCommand) -> Int? {
        if exercises.indices.contains(cmd.ex), cmd.name.isEmpty || Self.key(exercises[cmd.ex].name) == Self.key(cmd.name) { return cmd.ex }
        if cmd.name.isEmpty { return nil }
        return exercises.firstIndex { Self.key($0.name) == Self.key(cmd.name) }
    }

    /// The watch's own guess of what the phone will do with `cmd` — the
    /// same edits AppState makes.
    func applying(_ cmd: WatchCommand) -> WatchState {
        if !cmd.session.isEmpty && cmd.session != id { return self }
        var s = self
        func editSet(_ f: (inout WSet) -> Void) -> WatchState {
            guard let i = exerciseIndex(cmd), s.exercises[i].sets.indices.contains(cmd.set) else { return self }
            f(&s.exercises[i].sets[cmd.set])
            return s
        }
        switch cmd.cmd {
        case WatchCommand.logSet:
            guard let i = exerciseIndex(cmd), s.exercises[i].sets.indices.contains(cmd.set) else { return self }
            let e = s.exercises[i]
            s.exercises[i].sets[cmd.set].w = cmd.w
            s.exercises[i].sets[cmd.set].r = cmd.r
            s.exercises[i].sets[cmd.set].t = cmd.t
            s.exercises[i].sets[cmd.set].d = cmd.d
            s.exercises[i].sets[cmd.set].done = true
            s.rest = WRest(endsAt: cmd.at + Int64(e.restSec) * 1000, total: e.restSec, ex: e.name)
            return s
        case WatchCommand.undoSet: return editSet { $0.done = false }
        case WatchCommand.effort: return editSet { $0.e = cmd.effort }
        case WatchCommand.addSet:
            guard let i = exerciseIndex(cmd) else { return self }
            s.exercises[i].sets.append(WSet(pw: s.exercises[i].sets.last?.pw ?? ""))
            return s
        case WatchCommand.restSkip:
            s.rest = nil
            return s
        case WatchCommand.restAdd:
            guard var r = s.rest else { return self }
            r.endsAt += Int64(cmd.sec) * 1000
            r.total += cmd.sec
            s.rest = r
            return s
        case WatchCommand.finish:
            s.active = false
            s.finished = true
            s.rest = nil
            return s
        default:
            return self
        }
    }

    /// The phone's snapshot plus the watch's commands it hasn't applied yet.
    func withPending(_ pending: [WatchCommand]) -> WatchState {
        pending.filter { !acks.contains($0.id) }.reduce(self) { $0.applying($1) }
    }

    func toJson() -> String {
        var o: [String: Any] = [
            "v": WatchPaths.version, "active": active, "id": id, "type": type, "title": title, "startedAt": startedAt,
            "exercises": exercises.map(\.json), "acks": acks, "finished": finished, "sentAt": sentAt,
        ]
        o["rest"] = rest?.json ?? NSNull()
        return jsonString(o)
    }

    static func fromJson(_ text: String) -> WatchState? {
        guard let o = parseObject(text) else { return nil }
        return WatchState(
            active: o.bool("active"), id: o.str("id"), type: o.str("type"), title: o.str("title"),
            startedAt: o.int64("startedAt") ?? 0,
            exercises: (o["exercises"] as? [Any])?.compactMap { ($0 as? [String: Any]).map(WExercise.init(json:)) } ?? [],
            rest: (o["rest"] as? [String: Any]).flatMap(WRest.init(json:)),
            acks: (o["acks"] as? [Any])?.compactMap { $0 as? String } ?? [],
            finished: o.bool("finished"), sentAt: o.int64("sentAt") ?? 0
        )
    }

    /// [[i]] or [[i, partner]] in plan order — WorkoutView's grouping.
    static func groups(_ exs: [WExercise]) -> [[Int]] {
        var seen = Set<Int>()
        var out: [[Int]] = []
        for (i, ex) in exs.enumerated() where !seen.contains(i) {
            let partner = ex.superset.isEmpty ? nil : exs.indices.first { $0 != i && exs[$0].superset == ex.superset }
            if let p = partner, p > i { seen.formUnion([i, p]); out.append([i, p]) }
            else { seen.insert(i); out.append([i]) }
        }
        return out
    }

    /// "8-10" → "8" · "AMRAP" → "".
    static func firstNumber(_ s: String) -> String {
        guard let r = s.range(of: #"\d+"#, options: .regularExpression) else { return "" }
        return String(s[r])
    }

    private static func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }
}

/// A watch workout's numbers. The Apple Watch saves its HKWorkout itself,
/// so the iPhone only ever receives this from a Wear OS watch — it's here
/// so the two protocols stay identical.
nonisolated struct WorkoutSummary: Equatable, Sendable {
    var start: Int64
    var end: Int64
    var type = ""
    var kcal: Double?
    var avgHr: Double?
    var maxHr: Double?

    var json: [String: Any] {
        var o: [String: Any] = ["start": start, "end": end, "type": type, "hr": [Any]()]
        if let kcal { o["kcal"] = kcal }
        if let avgHr { o["avgHr"] = avgHr }
        if let maxHr { o["maxHr"] = maxHr }
        return o
    }

    init(start: Int64, end: Int64, type: String = "", kcal: Double? = nil, avgHr: Double? = nil, maxHr: Double? = nil) {
        self.start = start; self.end = end; self.type = type; self.kcal = kcal; self.avgHr = avgHr; self.maxHr = maxHr
    }

    init?(json o: [String: Any]) {
        guard let s = o.int64("start"), let e = o.int64("end") else { return nil }
        self.init(start: s, end: e, type: o.str("type"), kcal: o.double("kcal"), avgHr: o.double("avgHr"), maxHr: o.double("maxHr"))
    }
}

nonisolated struct WatchCommand: Equatable, Sendable {
    var id: String
    /// When it happened on the wrist (epoch ms) — a set logged offline
    /// starts its rest from then, not from when the phone heard about it.
    var at: Int64
    var cmd: String
    var session = ""
    var ex = -1
    var name = ""
    var set = -1
    var w = "", r = "", t = "", d = ""
    var effort = ""
    var sec = 0
    var rpe = 0
    var workout: WorkoutSummary?

    static let logSet = "logSet"
    static let undoSet = "undoSet"
    static let effort = "effort"
    static let addSet = "addSet"
    static let restSkip = "restSkip"
    static let restAdd = "restAdd"
    static let finish = "finish"
    /// "Send me the current state" — the watch app just opened.
    static let sync = "sync"
    static let workout = "workout"

    func toJson() -> String {
        var o: [String: Any] = [
            "v": WatchPaths.version, "id": id, "at": at, "cmd": cmd, "session": session, "ex": ex, "name": name, "set": set,
            "w": w, "r": r, "t": t, "d": d, "effort": effort, "sec": sec, "rpe": rpe,
        ]
        if let workout { o["workout"] = workout.json }
        return jsonString(o)
    }

    static func fromJson(_ text: String) -> WatchCommand? {
        guard let o = parseObject(text) else { return nil }
        let id = o.str("id"), cmd = o.str("cmd")
        guard !id.isEmpty, !cmd.isEmpty else { return nil }
        return WatchCommand(
            id: id, at: o.int64("at") ?? 0, cmd: cmd, session: o.str("session"), ex: o.int("ex") ?? -1, name: o.str("name"),
            set: o.int("set") ?? -1, w: o.str("w"), r: o.str("r"), t: o.str("t"), d: o.str("d"), effort: o.str("effort"),
            sec: o.int("sec") ?? 0, rpe: o.int("rpe") ?? 0,
            workout: (o["workout"] as? [String: Any]).flatMap(WorkoutSummary.init(json:))
        )
    }
}

// MARK: - Lenient JSON (a field of the wrong type reads as missing)

nonisolated private func parseObject(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

nonisolated private func jsonString(_ o: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

nonisolated private extension Dictionary where Key == String, Value == Any {
    /// JSONSerialization hands numbers and booleans back as NSNumber —
    /// a Bool must not read as 1, nor a number as true.
    private func isBool(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    func str(_ k: String) -> String {
        if let s = self[k] as? String { return s }
        if let n = self[k] as? NSNumber, !isBool(n) { return n.stringValue }
        return ""
    }

    func bool(_ k: String) -> Bool {
        guard let v = self[k], isBool(v) else { return false }
        return (v as? Bool) ?? false
    }

    func double(_ k: String) -> Double? {
        guard let v = self[k], !isBool(v), let n = v as? NSNumber else { return nil }
        return n.doubleValue
    }

    func int64(_ k: String) -> Int64? { double(k).map { Int64($0) } }
    func int(_ k: String) -> Int? { double(k).map { Int($0) } }
}
