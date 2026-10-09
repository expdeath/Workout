import Foundation

/// Direct Gemini API integration — ports src/api/gemini.js function-for-
/// function. No backend: the app calls generativelanguage.googleapis.com
/// straight from the device, same as the web app, with the same three-
/// model fallback ladder and the same deterministic guardrails on the
/// model's suggested weights.
enum Gemini {

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        case noApiKey
        case noConsent
        case server(String)
        case rateLimited(retryDelay: Int)
        case overloaded(model: String)
        case blocked(String)
        case http(Int, String)
        case empty
        case message(String)

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "No Gemini API key set. Go to Settings to add one."
            case .server(let m): return m
            case .noConsent: return "The AI coach is off — turn it on in Settings → AI Coach. Your data only goes to Google Gemini with your OK."
            case .rateLimited: return "Rate limit hit twice. Wait a minute and try again."
            case .overloaded(let m): return "\(m) is overloaded."
            case .blocked(let r): return "Request blocked by Gemini: \(r)"
            case .http(let s, let m): return "Gemini API error (\(s)): \(m)"
            case .empty: return "Empty response from Gemini."
            case .message(let m): return m
            }
        }
    }

    // Models to try in order — if one is overloaded, try the next.
    // 2.5 Flash was dropped — Google now 404s it for new API keys.
    private static let models = ["gemini-3.5-flash", "gemini-3.1-flash-lite", "gemini-3.6-flash"]

    // 3.5+ Flash models take thinkingLevel; the default burns tokens and truncates.
    private static func supportsThinkingLevel(_ model: String) -> Bool {
        model.range(of: #"^gemini-3\.[5-9]-flash$"#, options: .regularExpression) != nil
    }

    // MARK: - Workout database (menu, not a script)

    private static let workoutDB = """
    Exercise menu — staples exist ONLY to anchor long-term progression tracking on a couple of numbers per split, not to be run unchanged every time. Per session, keep AT MOST 1-2 staples (whichever the athlete is actively progressing) and fill the remaining slots from that day's pool — favor picks not seen in the last 2-3 sessions of the same split. Respect equipment limits. 1-2 core finishers may be appended to any lifting day.

    PUSH DAY — Warm-up: 15min Stairmaster OR light warm-up sets of the first press.
    Staples:
    - Flat Dumbbell Press 3x10-12 (alt: Seated Chest Press Machine, Barbell Bench Press)
    - Incline Dumbbell Press 3x10-12 (alt: Incline Machine Press, Low-to-High Cable Fly)
    - Machine Shoulder Press 3x10-12 (alt: Seated Dumbbell Shoulder Press)
    - Cable Lateral Raise 3x12-15 (alt: Dumbbell Lateral Raise)
    - Rope Tricep Pushdown 3x12-15 (alt: Straight-Bar Pushdown)
    Pool: Pec Deck Fly 3x12-15 · Cable Crossover 3x12-15 · Machine Dips 3x8-10 (alt: Bench Dips) · Overhead Rope Tricep Extension 3x10-12 · Skull Crushers 3x10-12 · Close-Grip Bench Press 3x8-10 · Arnold Press 3x10-12 · Push-Ups 3xAMRAP (finisher)
    Cooldown: doorway chest stretch, overhead tricep stretch.

    PULL DAY — Warm-up: 15min stationary bike OR light first-row sets.
    Staples:
    - Chest Supported Row 3x8-10 (alt: Seated Cable Row)
    - Lat Pulldown 3x8-10 (alt: Assisted Pull-Up, Neutral-Grip Pulldown)
    - Machine Rear Delt Fly 3x12-15 (alt: Face Pull)
    - Cable Curl 3x10-12 (alt: Dumbbell Curl)
    Pool: One-Arm Dumbbell Row 3x8-10/side · Straight-Arm Pulldown 3x12-15 · Barbell Row 3x8-10 · Hammer Curl 3x10-12 · Incline Dumbbell Curl 3x10-12 · Preacher Curl 3x10-12 · Dumbbell Shrug 3x12-15 · Back Extension 3x12 · Romanian Deadlift 3x8-10 (also fits Legs)
    Cooldown: lat stretch, bicep stretch.

    LEG DAY — Warm-up: 15min stationary bike + bodyweight squats x10.
    Staples:
    - Leg Press 3x10-12 (alt: Hack Squat, Goblet Squat)
    - Seated Leg Curl 3x10-12 (alt: Lying Leg Curl, Romanian Deadlift)
    - Leg Extension 3x12-15
    - Calf Press 3x15 (alt: Standing Calf Raise)
    Pool: Bulgarian Split Squat 3x8-10/side · Walking Lunges 3x10/side · Dumbbell Step-Ups 3x10/side · Hip Thrust 3x10-12 · Adductor Machine 3x12-15 · Abductor Machine 3x12-15 · Single-Leg Press 3x10/side · Smith Machine Squat 3x8-10
    Cooldown: quad stretch, hamstring stretch.

    CORE FINISHERS (append 1-2 to any day): Plank 3x45s · Side Plank 2x30s/side · Cable Crunch 3x12-15 · Hanging Knee Raise 3x10-12 · Pallof Press 3x10/side · Dead Bug 3x10/side · Russian Twist 3x20 · Ab Wheel Rollout 3x8-10

    CORE DAY (standalone session) — Warm-up: 5min easy bike + cat-cow x10.
    Staples:
    - Hanging Leg Raise 3x10-12 (alt: Hanging Knee Raise, Captain's Chair Knee Raise)
    - Cable Crunch 3x12-15 (alt: Weighted Sit-Up)
    - Pallof Press 3x10/side (alt: Standing Cable Woodchop)
    Pool: Weighted Plank 3x45-60s · Side Plank 2x30-45s/side · Ab Wheel Rollout 3x8-10 · Dead Bug 3x10/side · Russian Twist 3x20 · Hollow Hold 3x20-30s · Back Extension 3x12 (anti-extension balance) · Farmer's Carry 3x40m (anti-lateral flexion)
    Cooldown: cobra stretch, seated spinal twist.

    ACTIVE RECOVERY — Option 1: 30min stationary bike or incline walk, zone 2.
    Option 2: 3 rounds — dead bugs x10/side, bird dog x10/side, plank 45s, side plank 30s/side, hollow hold 20-30s.
    Option 3: 20min easy swim or rowing machine + 10min stretching.

    CARDIO DAY — Option 1: 35-45min zone 2 — stationary bike, incline treadmill walk, stairmaster, rowing machine, or easy run.
    Option 2: intervals — 10min easy bike, then 8 × (1min hard / 2min easy), 5min cooldown walk.
    Option 3: 25-30min run or 5k treadmill at steady pace.
    Option 4: 3 rounds — 500m row, 1min jump rope, 10 kettlebell swings, 1min rest.
    Finish: 5min full-body stretch.

    STRETCH & MOBILITY DAY — 10min easy bike, then 2 rounds: cat-cow x10, world's greatest stretch x5/side, 90/90 hip switches x10/side, couch stretch 45s/side, hamstring floss x10/side, thoracic wall opener 45s/side, doorway chest stretch 45s/side, deep squat hold 30s. Optional extras: pigeon pose 45s/side, child's pose 60s, band shoulder dislocates x10, calf stretch 45s/side.

    FULL BODY MIX (fun day) — pick 5-6, 2 sets each, moderate load, superset pairs, 60s rests: leg press, goblet squat, chest press machine, chest supported row, lat pulldown, hip thrust, cable lateral raise, cable curl, rope pushdown, kettlebell swing, plank 45s.
    """

    private static let defaultProfile = "Recreational lifter, trains Push/Pull/Legs at a commercial gym. Goals: strength, muscle, sustainable habits. Sessions 45-75 min, 4-5 per week."

    private static func coachRules() -> String {
        let profile = LocalStore.shared.backup.aiSettings.profile.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = profile.isEmpty ? defaultProfile : profile
        return """
        You are this person's long-term strength coach. PROFILE: \(p)
        Don't prohibit exercises; prefer supported/machine variations when appropriate, add technique cues. Adapt to today's check-in (soreness, tightness, energy).
        Progression: recommend small weight increases, extra reps, or holding, based on logged history. NEVER increase load if recovery looks poor. If returning from 1+ week break: reduce volume, avoid failure, reduce weights, expect DOMS.
        Logged sets may carry the athlete's own effort tag — (easy) = clear room to progress, (good) = about right, (grind) = near-failure. Never add load to a lift whose last sets were grinds; treat all-easy sets as a green light for a bigger jump.
        Rotate exercises HARD — before picking, find the most recent session of the SAME split in the TRAINING LOG and compare exercise-by-exercise: if 3+ names match, that's a repeat, not a plan. The workout database separates STAPLES (keep AT MOST 1-2 per session — only the ones you're actively tracking numeric progress on) from a rotation POOL: fill every other slot from the pool, preferring picks not used in that split's last 2-3 sessions. Never send out the exact same exercise list two sessions running for the same split. Do not invent history that isn't in the log. Occasionally append a core finisher to a lifting day when time allows.
        VARIETY: training is NOT a rigid Push/Pull/Legs loop. Read the history — after 3+ consecutive lifting days, or when no cardio or mobility day appears in the last 7-10 days, schedule a Cardio or Stretch & Mobility day (recovery quality decides which). If the MUSCLE BALANCE note flags Core as untrained 10+ days, schedule a standalone Core day from the CORE DAY block instead of just appending a finisher — it needs to compete for a rotation slot like Cardio/Stretch do, not stay an afterthought. A Full Body mix day is a good occasional change of pace. If the check-in states a session preference, honor it — it overrides the rotation. Use the LONG-TERM TRAINING SUMMARY for progression decisions and split balance; the recent TRAINING LOG shows exact numbers for the last sessions.
        Be direct and analytical. No hype. State uncertainty when the data is thin.
        """
    }

    private static func planSystem() -> String {
        let routine = LocalStore.shared.backup.aiSettings.routine.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(coachRules())\n\nBASE WORKOUT DATABASE:\n\(routine.isEmpty ? workoutDB : routine)"
    }

    private static let jsonSpec = """
    BE EXTREMELY CONCISE in every string; total response must stay under 900 tokens. Field rules:
    {"sessionType":"Push|Pull|Legs|Full Body|Core|Cardio|Stretch & Mobility|Active Recovery|Rest Day",
    "title":"max 6 words",
    "recoveryScore":0-100,
    "reasoning":"max 2 short sentences",
    "warmup":["max 3 items, max 8 words each"],
    "exercises":[{"name":"","sets":3,"reps":"10-12","rpe":"7-8","rest":"90s","notes":"max 10 words or empty","alt":"max 5 words or empty","suggestedWeight":"e.g. 24kg or empty","superset":"A/B or empty"}],
    "cardio":{"desc":"max 8 words","duration":"e.g. 15min"} or null,
    "cooldown":["max 3 items, max 6 words each"],
    "estTimeMin":number including 24min walking,
    "concerns":"max 12 words or empty"}
    Max 6 exercises. If Rest Day, exercises=[]. For Cardio, Stretch & Mobility, Active Recovery, or Core put the circuit/intervals/stretches/core-moves in exercises (sets=rounds, reps=duration or count, weight empty).
    Supersets: when time is tight or two accessories pair well (non-competing muscles), give BOTH exercises the same "superset" letter and place them adjacently — the athlete alternates sets and shares the rest. Never superset heavy compounds.
    """

    private static let planSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "sessionType": ["type": "STRING", "enum": ["Push", "Pull", "Legs", "Full Body", "Core", "Cardio", "Stretch & Mobility", "Active Recovery", "Rest Day"]],
            "title": ["type": "STRING"],
            "recoveryScore": ["type": "INTEGER"],
            "reasoning": ["type": "STRING"],
            "warmup": ["type": "ARRAY", "items": ["type": "STRING"]],
            "exercises": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING"], "sets": ["type": "INTEGER"], "reps": ["type": "STRING"],
                        "rpe": ["type": "STRING"], "rest": ["type": "STRING"], "notes": ["type": "STRING"],
                        "alt": ["type": "STRING"], "suggestedWeight": ["type": "STRING"], "superset": ["type": "STRING"],
                    ],
                    "required": ["name", "sets", "reps"],
                ],
            ],
            "cardio": ["type": "OBJECT", "nullable": true, "properties": ["desc": ["type": "STRING"], "duration": ["type": "STRING"]]],
            "cooldown": ["type": "ARRAY", "items": ["type": "STRING"]],
            "estTimeMin": ["type": "INTEGER"],
            "concerns": ["type": "STRING"],
        ],
        "required": ["sessionType", "exercises", "estTimeMin"],
    ]

    // MARK: - Deterministic guardrails on suggested weights

    private static let maxJumpFactor = 1.15 // suggested load ≤ 15% over last logged
    private static let minJumpKg = 2.5
    private static let plateStepKg = 2.5
    private static let maxWeightKg = 200.0

    @discardableResult
    private static func capSuggestedWeight(_ ex: inout Plan.Exercise, _ history: [Session]) -> Bool {
        guard let g = Stats.firstMatch(#"([\d.]+)"#, in: ex.suggestedWeight), let numStr = g[safe: 1] ?? nil, let w = Double(numStr) else { return false }
        let lp = Stats.lastPerformance(history, ex.name)
        let lastW = lp?.sets.compactMap { Double($0.weight) }.max() ?? 0
        let cap = lastW > 0 ? min(max(lastW * maxJumpFactor, lastW + minJumpKg), maxWeightKg) : maxWeightKg
        guard w > cap else { return false }
        let rounded = (cap / plateStepKg).rounded() * plateStepKg
        ex.suggestedWeight = "\(fmtKg(rounded))kg"
        return true
    }

    private static func fmtKg(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    static func sanitizePlan(_ plan: Plan, _ history: [Session], _ checkin: Checkin) -> Plan {
        var p = plan
        var changed = false
        if p.exercises.count > 6 {
            p.exercises = Array(p.exercises.prefix(6))
            changed = true
        }
        for i in p.exercises.indices {
            if capSuggestedWeight(&p.exercises[i], history) { changed = true }
        }
        let avail = Int(checkin.timeAvail) ?? 60
        if p.estTimeMin > avail + 24 + 10 {
            p.estTimeMin = avail + 24
            changed = true
        }
        if changed {
            LocalStore.shared.logEvent(type: "plan_sanitized", data: ["sessionType": .string(p.sessionType)])
        }
        return p
    }

    // MARK: - User message

    private static let wish: [String: String] = [
        "lift": "The athlete wants to LIFT today — pick the right strength session for the split balance.",
        "cardio": "The athlete asked for a CARDIO day — build it around conditioning (bike/stairs/incline walk/intervals), no lifting session.",
        "stretch": "The athlete asked for a STRETCH & MOBILITY day — a full mobility/flexibility session, no heavy lifting.",
        "core": "The athlete asked for a CORE day — build a standalone core session from the CORE DAY block, no other lifting.",
        "surprise": "The athlete asked you to SURPRISE them — build something genuinely different from the recent sessions (mixed circuit, superset full-body, conditioning + core, new variations). Keep it safe and equipment-realistic, but make it fun.",
    ]

    private static func baselineComparison(_ checkin: Checkin, _ history: [Session], _ healthLog: [HealthRow]) -> String {
        guard let health = checkin.health, !health.isEmpty else { return "" }
        let today = Stats.parseHealthNumbers(health)
        let base = Stats.healthBaseline(history, healthLog)
        var lines: [String] = []
        if let t = today.hrv, let b = base.hrv {
            let d = Int((((t - b) / b) * 100).rounded())
            lines.append("HRV \(fmtKg(t)) vs 30-day avg \(fmtKg(b)) (\(d >= 0 ? "+" : "")\(d)%)\(d <= -10 ? " — recovery below normal" : "")")
        }
        if let t = today.rhr, let b = base.rhr {
            let d = Int((((t - b) / b) * 100).rounded())
            lines.append("RHR \(fmtKg(t)) vs 30-day avg \(fmtKg(b)) (\(d >= 0 ? "+" : "")\(d)%)\(d >= 7 ? " — elevated, possible fatigue/illness" : "")")
        }
        if let t = today.sleepH, let b = base.sleepH {
            let d = Int((((t - b) / b) * 100).rounded())
            lines.append("Sleep \(fmtKg(t))h vs 30-day avg \(fmtKg(b))h\(d <= -20 ? " — clearly short, reduce intensity" : "")")
        }
        if let t = today.respRate, let b = base.respRate {
            let d = Int((((t - b) / b) * 100).rounded())
            lines.append("Respiratory rate \(fmtKg(t)) vs avg \(fmtKg(b))\(d >= 10 ? " — elevated, possible illness" : "")")
        }
        if let t = today.wristC, let b = base.wristC {
            let d = ((t - b) * 10).rounded() / 10
            lines.append("Wrist temp \(fmtKg(t))°C vs avg \(fmtKg(b))°C\(d >= 0.4 ? " (+\(fmtKg(d))°C — possible illness/strain, be conservative)" : "")")
        }
        return lines.isEmpty ? "" : "Baseline comparison (computed): " + lines.joined(separator: "; ")
    }

    private static func sessionLogLine(_ h: Session) -> String {
        let exercises = h.plan.exercises.enumerated().map { (i, ex) -> String in
            let sets = (i < h.log.count ? h.log[i] : []).filter { $0.isLogged }
                .map { s -> String in s.formatted + (s.effort.isEmpty ? "" : "(\(s.effort))") }
                .joined(separator: ", ")
            return "\(ex.name) [\(sets.isEmpty ? "no sets logged" : sets)]"
        }.joined(separator: "; ")
        let outcome: String
        if h.finished {
            let rpe = h.fin.map { String($0.rpe) } ?? "?"
            var s = " | session RPE \(rpe)"
            if let d = h.durationMin { s += " | took \(d)min" }
            if let pain = h.fin?.pain, !pain.isEmpty { s += " | pain: \(pain)" }
            if let fb = h.fin?.feedback, !fb.isEmpty { s += " | notes: \(fb)" }
            outcome = s
        } else {
            outcome = " | NOT COMPLETED"
        }
        return "\(h.date) — \(h.plan.sessionType): \(exercises)\(outcome)"
    }

    static func buildUserMessage(_ checkin: Checkin, _ history: [Session], _ healthLog: [HealthRow] = [], template: SavedWorkout? = nil) -> String {
        let settings = LocalStore.shared.backup.aiSettings
        let recent = Array(history.suffix(6))
        let histText = recent.isEmpty
            ? "No logged sessions yet in this app. Treat as a fresh start — use the base workout database, moderate volume, and ask nothing (choose sensibly)."
            : recent.map(sessionLogLine).joined(separator: "\n")
        let daysSince: Int? = recent.isEmpty ? nil : Int(((Stats.dateMs(Helpers.todayStr()) - Stats.dateMs(recent.last!.date)) / 86400).rounded())
        let lastDebrief = recent.last?.debrief ?? ""

        let normalized = checkin.health.map { Stats.fmtHealthLine(Stats.parseHealthNumbers($0)) } ?? ""
        let trend = Stats.healthTrend(healthLog)
        let baselines = baselineComparison(checkin, history, healthLog)
        let deload = Stats.deloadSignal(history)
        let muscleGap = Stats.muscleGapNote(history)
        let goals = settings.goals.trimmingCharacters(in: .whitespacesAndNewlines)
        let equipment = settings.equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        let cueLines = settings.cueNotes.prefix(15).map { "- \($0.key): \($0.value)" }.joined(separator: "\n")

        let weekday = { () -> String in
            let f = DateFormatter(); f.dateFormat = "EEEE"; f.timeZone = .current
            return f.string(from: Date())
        }()

        var out = "\nTODAY: \(Helpers.todayStr()) (\(weekday))\n\n"
        out += "CHECK-IN:\n"
        out += "- Energy: \(checkin.energy)/10\n"
        out += "- Sleep last night: \(checkin.sleep)\n"
        out += "- Soreness: \(checkin.soreness)\(checkin.soreAreas.isEmpty ? "" : " (\(checkin.soreAreas))")\n"
        out += "- Lower back tight today: \(checkin.backTight ? "YES — adapt exercise selection" : "no")\n"
        out += "- Time available today (gym time, walking excluded): \(checkin.timeAvail) min\n"
        if let w = wish[checkin.wish] { out += "- SESSION PREFERENCE (honor this): \(w)\n" }
        if !checkin.prioritizeMuscle.isEmpty {
            out += "- Athlete asked to prioritize \(checkin.prioritizeMuscle) today (untrained 10+ days) — bias exercise selection and/or session type toward this group if recovery allows.\n"
        }
        if let bw = Double(checkin.bodyKg), bw > 0 { out += "- Body weight today: \(checkin.bodyKg)kg\n" }
        if !checkin.notes.isEmpty { out += "- Other notes: \(checkin.notes)\n" }

        out += "\nAPPLE HEALTH DATA (raw Watch payload, may be empty):\n"
        out += (checkin.health?.isEmpty == false ? checkin.health! : "None provided today — rely on check-in + history.") + "\n"
        if !normalized.isEmpty { out += "Normalized by app (sleep deduped to hours — trust these units): \(normalized)\n" }
        if !trend.isEmpty { out += "WATCH DATA TREND (daily, most recent last):\n\(trend)\n" }
        if !baselines.isEmpty { out += "\(baselines)\n" }
        if let deload { out += "\nDELOAD WATCH (computed): \(deload.reason) Honor this unless today's readiness is clearly excellent.\n" }
        if !muscleGap.isEmpty { out += "\n\(muscleGap)\n" }
        if !goals.isEmpty { out += "\nATHLETE'S STATED GOALS (steer selection and progression toward these):\n\(goals)\n" }
        if !equipment.isEmpty { out += "\nGYM EQUIPMENT & LIMITS (HARD CONSTRAINT — never prescribe anything unavailable; respect load limits):\n\(equipment)\n" }
        if !cueLines.isEmpty { out += "\nATHLETE'S OWN EXERCISE NOTES (persistent cue cards — respect them when picking/prescribing):\n\(cueLines)\n" }

        out += "\nPROGRESSION TARGETS (computed deterministically from the logs — anchor suggestedWeight on these):\n"
        let targets = Stats.progressionTargets(history)
        out += (targets.isEmpty ? "No logged sets yet." : targets) + "\n"

        out += "\nLONG-TERM TRAINING SUMMARY (compressed from full history):\n"
        let summary = AIContext.buildLongTermSummary(history)
        out += (summary.isEmpty ? "Not enough history yet — rely on the recent log below." : summary) + "\n"

        out += "\nTRAINING LOG (last sessions in detail, most recent last):\n\(histText)\n"
        if let daysSince {
            out += "Days since last logged session: \(daysSince)\(daysSince >= 7 ? " — RETURNING FROM BREAK, apply reduced-volume rules." : "")\n"
        }
        if !lastDebrief.isEmpty { out += "\nYOUR OWN COACHING NOTE AFTER THE LAST SESSION (follow through on it): \(lastDebrief)\n" }

        out += "\n\(template.map(templateInstruction) ?? "Decide the right session for today and build it.") \(jsonSpec)"
        return out
    }

    /// The athlete picked one of their saved workouts (templateInstruction
    /// in gemini.js). Keep-exact: the coach only fills weights and cues,
    /// and Workouts.enforceExact holds it to that.
    static func templateInstruction(_ w: SavedWorkout) -> String {
        let brief = Workouts.brief(w)
        if !w.adapt {
            return """
            TODAY THE ATHLETE IS DOING THEIR SAVED WORKOUT — \(brief)

            Use EXACTLY these exercises, in this order, with these sets and reps — do not add, remove, reorder or swap anything (a trainer wrote it; respect it). Where a weight is given, keep it. Where none is given, fill suggestedWeight from PROGRESSION TARGETS / the training log. Add short form cues in notes only when useful. Set sessionType to the closest match and title to the workout's name. If today's recovery data or check-in is worrying, say so in "concerns" — but still keep the workout as written.
            """
        }
        return """
        TODAY THE ATHLETE WANTS TO DO THEIR SAVED WORKOUT, ADAPTED TO TODAY — \(brief)

        Use it as the base and keep its intent and exercise choices. Adapt only where today's check-in, recovery data, soreness, pain or time make it sensible: fewer sets or lighter loads on a poor day, a safer swap for something that would aggravate soreness, trimming to fit the time. Fill suggestedWeight from the training log where none is given. In "reasoning", say plainly what you changed from the saved workout and why (or that you kept it as written).
        """
    }

    // MARK: - Networking core

    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { struct Part: Decodable { var text: String? }; var parts: [Part]? }
            var content: Content?
            var finishReason: String?
        }
        struct PromptFeedback: Decodable { var blockReason: String? }
        var candidates: [Candidate]?
        var promptFeedback: PromptFeedback?
    }

    private static func endpoint(_ model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    /// Low-level call: posts one generateContent request and extracts the
    /// text from the first candidate. Callers interpret rate-limit/
    /// overload status codes themselves since the two callers (plan vs
    /// text/chat calls) react to them differently (retry ladder vs
    /// simple model fallback).
    private static func post(model: String, systemInstruction: String, contents: [[String: Any]], generationConfig: [String: Any], timeout: TimeInterval) async throws -> (text: String, response: HTTPURLResponse, data: Data) {
        // every Gemini request passes here: nothing leaves without consent
        guard AIConsent.allowed else { throw GeminiError.noConsent }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": contents,
            "generationConfig": generationConfig,
        ]
        var req: URLRequest
        if Cloud.shared.proActive {
            // COACH Pro: the COACH server adds the owner's key (functions/index.js)
            req = URLRequest(url: URL(string: "\(Cloud.functionsBase)/coach")!)
            req.setValue("Bearer \(try await Cloud.shared.idToken())", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "body": body])
        } else {
            guard !Cloud.shared.geminiKey.isEmpty else { throw GeminiError.noApiKey }
            req = URLRequest(url: endpoint(model))
            req.setValue(Cloud.shared.geminiKey, forHTTPHeaderField: "X-goog-api-key")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GeminiError.message("No HTTP response") }

        // the COACH server's own refusals (not Pro, consent off, today's
        // limit) — final: another model won't change the answer
        if Cloud.shared.proActive, [401, 402, 403].contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw GeminiError.server(msg ?? "COACH Pro couldn't answer — try again.")
        }

        if http.statusCode == 429 {
            var retryDelay = 45
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = obj["error"] as? [String: Any], let msg = error["message"] as? String {
                if msg.contains("limit: 0") {
                    throw GeminiError.message("Your API key has no quota (limit: 0). This usually means your key is an old standard key that Google has blocked since June 2026. Go to aistudio.google.com → API Keys → Create a NEW API key (it will be an auth key automatically). Then paste it in Settings.")
                }
                if let g = Stats.firstMatch(#"retry in ([\d.]+)s"#, in: msg), let s = g[safe: 1] ?? nil, let d = Double(s) {
                    retryDelay = Int(ceil(d))
                }
            }
            throw GeminiError.rateLimited(retryDelay: min(retryDelay, 90))
        }
        if http.statusCode == 503 { throw GeminiError.overloaded(model: model) }
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let block = decoded.promptFeedback?.blockReason { throw GeminiError.blocked(block) }
        guard let candidate = decoded.candidates?.first else { throw GeminiError.message("No candidates in Gemini response — the request may have been filtered.") }
        if candidate.finishReason == "SAFETY" { throw GeminiError.message("Response blocked by Gemini safety filters. Try again.") }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined(separator: "\n")
        guard !text.isEmpty else { throw GeminiError.message("Empty response from Gemini. Finish reason: \(candidate.finishReason ?? "unknown")") }
        return (text, http, data)
    }

    /// Strips ```json fences, extracts the {...} span, and repairs a
    /// truncated tail by closing open brackets/strings — ports
    /// parsePlan() in src/utils/parser.js. Structured output makes this
    /// mostly defensive (maxOutputTokens truncation is the real risk).
    private static func repairAndDecodePlan(_ raw: String) throws -> Plan {
        var s = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = s.firstIndex(of: "{") else { throw GeminiError.message("no JSON in response") }
        s = String(s[start...])

        if let end = s.lastIndex(of: "}") {
            let clean = String(s[...end])
            if let data = clean.data(using: .utf8), let plan = try? Plan.fromAI(data) {
                return plan
            }
        }

        // Repair pass: walk the string, track open structures, close them.
        var out = ""
        var stack: [Character] = []
        var inStr = false
        var esc = false
        for ch in s {
            out.append(ch)
            if inStr {
                if esc { esc = false }
                else if ch == "\\" { esc = true }
                else if ch == "\"" { inStr = false }
                continue
            }
            if ch == "\"" { inStr = true }
            else if ch == "{" { stack.append("}") }
            else if ch == "[" { stack.append("]") }
            else if ch == "}" || ch == "]" { if !stack.isEmpty { stack.removeLast() } }
        }
        if inStr { out.append("\"") }
        while out.hasSuffix(",") || out.hasSuffix(", ") { out = String(out.dropLast()) }
        while let last = stack.popLast() { out.append(last) }
        guard let data = out.data(using: .utf8) else { throw GeminiError.message("could not repair JSON") }
        return try Plan.fromAI(data)
    }

    private static func callGemini(checkin: Checkin, history: [Session], model: String, healthLog: [HealthRow], template: SavedWorkout? = nil) async throws -> Plan {
        let userMsg = buildUserMessage(checkin, history, healthLog, template: template)
        LocalStore.shared.logEvent(type: "ai_request", data: ["model": .string(model)])
        let started = Date()

        var config: [String: Any] = [
            "maxOutputTokens": 4000,
            "temperature": checkin.wish == "surprise" ? 0.9 : 0.65,
            "responseMimeType": "application/json",
            "responseSchema": planSchema,
        ]
        if supportsThinkingLevel(model) { config["thinkingConfig"] = ["thinkingLevel": "low"] }

        do {
            let text: String
            do {
                text = try await post(
                    model: model, systemInstruction: planSystem(),
                    contents: [["role": "user", "parts": [["text": userMsg]]]],
                    generationConfig: config, timeout: 60
                ).text
            } catch let e as URLError where e.code == .timedOut {
                throw GeminiError.message("Request timed out after 60 seconds. The AI might be overloaded — try again.")
            }
            LocalStore.shared.logEvent(type: "ai_response", data: ["model": .string(model), "chars": .number(Double(text.count)), "raw": .string(text)])
            let plan = try repairAndDecodePlan(text)
            return sanitizePlan(plan, history, checkin)
        } catch {
            LocalStore.shared.logEvent(type: "ai_error", data: ["model": .string(model), "message": .string(error.localizedDescription), "latencyMs": .number(Date().timeIntervalSince(started) * 1000)])
            throw error
        }
    }

    private static func callGeminiText(_ userMsg: String, maxTokens: Int, eventType: String) async throws -> String {
        guard Cloud.shared.aiReady else { throw GeminiError.noApiKey }
        var lastErr: Error = GeminiError.message("no models tried")
        for model in models.prefix(2) {
            var config: [String: Any] = ["maxOutputTokens": maxTokens + 1000, "temperature": 0.6]
            if supportsThinkingLevel(model) { config["thinkingConfig"] = ["thinkingLevel": "minimal"] }
            do {
                let (text, _, _) = try await post(
                    model: model, systemInstruction: coachRules(),
                    contents: [["role": "user", "parts": [["text": userMsg]]]],
                    generationConfig: config, timeout: 20
                )
                LocalStore.shared.logEvent(type: eventType, data: ["model": .string(model), "raw": .string(text)])
                return text
            } catch {
                lastErr = error
            }
        }
        throw lastErr
    }

    // MARK: - Coach chat

    struct ChatMessage { var role: String; var text: String } // role: "user" | "coach"

    private static func sessionDetail(_ s: Session) -> String {
        let lines = s.plan.exercises.enumerated().map { (i, ex) -> String in
            let sets = (i < s.log.count ? s.log[i] : []).filter { $0.isLogged }.map(\.formatted).joined(separator: " ")
            return "\(ex.name): \(sets.isEmpty ? "—" : sets)"
        }
        var parts = ["\(s.date) \(s.plan.sessionType)\(s.durationMin.map { " · \($0)min" } ?? "")"]
        parts.append(contentsOf: lines)
        if let fin = s.fin {
            var line = "RPE \(fin.rpe)/10"
            if !fin.pain.isEmpty { line += " · pain: \(fin.pain)" }
            if !fin.feedback.isEmpty { line += " · feedback: \(fin.feedback)" }
            parts.append(line)
        }
        if let debrief = s.debrief, !debrief.isEmpty { parts.append("Debrief already given: \(debrief)") }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func askCoach(messages: [ChatMessage], history: [Session] = [], todayPlan: Session? = nil, healthLog: [HealthRow] = [], focusSession: Session? = nil) async throws -> String {
        guard Cloud.shared.aiReady else { throw GeminiError.noApiKey }
        let recent = history.suffix(3).map { h -> String in
            "\(h.date) \(h.plan.sessionType) RPE \(h.fin.map { String($0.rpe) } ?? "?")\(h.fin?.pain.isEmpty == false ? " pain: \(h.fin!.pain)" : "")"
        }.joined(separator: "; ")
        let plan = todayPlan.map { t -> String in
            "\(t.plan.sessionType) — \(t.plan.exercises.map(\.name).joined(separator: ", "))\(t.finished ? " (finished)" : " (in progress)")"
        } ?? "none generated yet"
        let trend = Stats.healthTrend(healthLog, n: 4)

        var system = "\(coachRules())\nYou are now CHATTING with the athlete (often mid-workout, phone in hand). Answer in 2-5 short sentences, plain text, no markdown, immediately practical. If they mention pain, be conservative and suggest the safe variation.\n"
        system += "CONTEXT — today's session: \(plan). Recent: \(recent.isEmpty ? "no logged sessions" : recent)."
        if !trend.isEmpty { system += "\nWatch data:\n\(trend)" }
        if let focusSession {
            system += "\nFOCUS — the athlete is viewing this logged session and asking about it:\n\(sessionDetail(focusSession))"
        }

        let contents: [[String: Any]] = messages.suffix(12).map {
            ["role": $0.role == "user" ? "user" : "model", "parts": [["text": $0.text]]]
        }

        var lastErr: Error = GeminiError.message("no models tried")
        for model in models.prefix(2) {
            var config: [String: Any] = ["maxOutputTokens": 1500, "temperature": 0.6]
            if supportsThinkingLevel(model) { config["thinkingConfig"] = ["thinkingLevel": "minimal"] }
            do {
                let (text, _, _) = try await post(model: model, systemInstruction: system, contents: contents, generationConfig: config, timeout: 25)
                LocalStore.shared.logEvent(type: "coach_chat", data: ["model": .string(model), "chars": .number(Double(text.count))])
                return text
            } catch { lastErr = error }
        }
        throw lastErr
    }

    // MARK: - "Make it harder"

    struct IntensifyOption { var kind: String; var target: String; var why: String; var exercise: Plan.Exercise? }
    struct IntensifyResult { var note: String; var options: [IntensifyOption] }

    private static let intensifySchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "note": ["type": "STRING"],
            "options": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "kind": ["type": "STRING", "enum": ["add", "extraSet", "replace"]],
                        "target": ["type": "STRING"],
                        "why": ["type": "STRING"],
                        "exercise": [
                            "type": "OBJECT", "nullable": true,
                            "properties": [
                                "name": ["type": "STRING"], "sets": ["type": "INTEGER"], "reps": ["type": "STRING"],
                                "rpe": ["type": "STRING"], "rest": ["type": "STRING"], "notes": ["type": "STRING"],
                                "alt": ["type": "STRING"], "suggestedWeight": ["type": "STRING"],
                            ],
                            "required": ["name", "sets", "reps"],
                        ],
                    ],
                    "required": ["kind", "why"],
                ],
            ],
        ],
        "required": ["options"],
    ]

    static func intensifyWorkout(today: Session, history: [Session], healthLog: [HealthRow] = []) async throws -> IntensifyResult {
        guard Cloud.shared.aiReady else { throw GeminiError.noApiKey }
        let p = today.plan
        let checkin = today.checkin
        let progress = p.exercises.enumerated().map { (i, ex) -> String in
            let done = (i < today.log.count ? today.log[i] : []).filter { $0.isLogged }.map(\.formatted).joined(separator: ", ")
            return "\(i + 1). \(ex.name) \(ex.sets)×\(ex.reps)\(ex.suggestedWeight.isEmpty ? "" : " @\(ex.suggestedWeight)") — sets logged: \(done.isEmpty ? "none yet" : done)"
        }.joined(separator: "\n")

        var recovery: [String] = []
        let t = Stats.healthTrend(healthLog, n: 5)
        if !t.isEmpty { recovery.append("Watch data trend:\n\(t)") }
        let todayNums = Stats.parseHealthNumbers(checkin?.health)
        let base = Stats.healthBaseline(history, healthLog)
        if let tv = todayNums.hrv, let b = base.hrv {
            let d = Int((((tv - b) / b) * 100).rounded())
            recovery.append("HRV today \(fmtKg(tv)) vs 30-day avg \(fmtKg(b)) (\(d >= 0 ? "+" : "")\(d)%)")
        }
        if let tv = todayNums.rhr, let b = base.rhr {
            let d = Int((((tv - b) / b) * 100).rounded())
            recovery.append("RHR today \(fmtKg(tv)) vs 30-day avg \(fmtKg(b)) (\(d >= 0 ? "+" : "")\(d)%)")
        }
        if let fatigue = Stats.fatigueSignal(history) { recovery.append(fatigue) }

        let recent = history.suffix(3).map { "\($0.date) \($0.plan.sessionType) RPE \($0.fin.map { String($0.rpe) } ?? "?")" }.joined(separator: "; ")
        let equipment = LocalStore.shared.backup.aiSettings.equipment.trimmingCharacters(in: .whitespacesAndNewlines)

        var userMsg = "The athlete is mid-session TODAY and feels strong — they tapped \"make it harder\" and want to extend this workout.\n\n"
        userMsg += "TODAY (\(today.date)) — \(p.sessionType), plan with live progress:\n\(progress)\n"
        userMsg += "Time budget: \(checkin?.timeAvail ?? "60") min gym time. Check-in this morning: energy \(checkin?.energy ?? 7)/10, sleep \(checkin?.sleep ?? "OK"), soreness \(checkin?.soreness ?? "None")\(checkin?.soreAreas.isEmpty == false ? " (\(checkin!.soreAreas))" : "").\n\n"
        userMsg += "RECOVERY DATA (today vs their own history):\n\(recovery.isEmpty ? "No watch data available — rely on check-in and training log." : recovery.joined(separator: "\n"))\n\n"
        userMsg += "PROGRESSION TARGETS (from logged history):\n\(Stats.progressionTargets(history).isEmpty ? "No logged sets yet." : Stats.progressionTargets(history))\n"
        userMsg += "RECENT SESSIONS: \(recent.isEmpty ? "none logged" : recent)\n"
        if !equipment.isEmpty { userMsg += "GYM EQUIPMENT & LIMITS (never suggest anything unavailable):\n\(equipment)\n" }
        userMsg += """

        Offer 2-3 concrete ways to make today harder — AT MOST ONE of each kind:
        - "add": ONE new exercise that fits the \(p.sessionType.isEmpty ? "current" : p.sessionType) split and the remaining time ("exercise" required, sets 2-3).
        - "extraSet": one extra set on the existing exercise that would benefit most ("target" = its exact name from the plan).
        - "replace": swap an exercise with NO sets logged yet for a harder variation ("target" = exact name of the exercise being replaced, "exercise" = the harder one). Skip this kind if everything is already started.
        Keep "why" under 10 words. Anchor any suggestedWeight on the logged history — no big jumps.
        "note": ONLY IF the recovery data above (sleep, HRV vs baseline, RHR, fatigue trend) suggests today isn't ideal for extra load, write ONE gentle supportive sentence reminding them of that specific data point — a soft nudge, never a prohibition, no scolding. If recovery looks fine, use an empty string.
        """

        var lastErr: Error = GeminiError.message("no models tried")
        for model in models.prefix(2) {
            var config: [String: Any] = ["maxOutputTokens": 2000, "temperature": 0.5, "responseMimeType": "application/json", "responseSchema": intensifySchema]
            if supportsThinkingLevel(model) { config["thinkingConfig"] = ["thinkingLevel": "low"] }
            do {
                let (text, _, _) = try await post(model: model, systemInstruction: coachRules(), contents: [["role": "user", "parts": [["text": userMsg]]]], generationConfig: config, timeout: 25)
                guard let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw GeminiError.message("could not parse intensify response")
                }
                let note = (obj["note"] as? String) ?? ""
                let names = Set(p.exercises.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
                var options: [IntensifyOption] = []
                for raw in (obj["options"] as? [[String: Any]]) ?? [] {
                    guard let kind = raw["kind"] as? String else { continue }
                    let target = (raw["target"] as? String) ?? ""
                    let why = (raw["why"] as? String) ?? ""
                    var exercise: Plan.Exercise? = nil
                    if let exObj = raw["exercise"] as? [String: Any], let name = exObj["name"] as? String, !name.isEmpty {
                        exercise = Plan.Exercise(
                            name: name, sets: (exObj["sets"] as? Int) ?? 3, reps: (exObj["reps"] as? String) ?? "",
                            rpe: (exObj["rpe"] as? String) ?? "7-8", rest: (exObj["rest"] as? String) ?? "90s",
                            notes: (exObj["notes"] as? String) ?? "", alt: (exObj["alt"] as? String) ?? "",
                            suggestedWeight: (exObj["suggestedWeight"] as? String) ?? ""
                        )
                    }
                    let valid: Bool
                    switch kind {
                    case "add": valid = exercise != nil
                    case "replace": valid = exercise != nil && names.contains(target.trimmingCharacters(in: .whitespaces).lowercased())
                    case "extraSet": valid = names.contains(target.trimmingCharacters(in: .whitespaces).lowercased())
                    default: valid = false
                    }
                    guard valid else { continue }
                    if var ex = exercise {
                        capSuggestedWeight(&ex, history)
                        exercise = ex
                    }
                    options.append(IntensifyOption(kind: kind, target: target, why: why, exercise: exercise))
                    if options.count >= 3 { break }
                }
                LocalStore.shared.logEvent(type: "ai_intensify", data: ["model": .string(model), "options": .array(options.map { .string($0.kind) }), "hasNote": .bool(!note.isEmpty)])
                return IntensifyResult(note: note, options: options)
            } catch { lastErr = error }
        }
        throw lastErr
    }

    // MARK: - Debrief / weekly / monthly

    static func generateDebrief(_ session: Session, _ history: [Session]) async throws -> String {
        let sets = session.plan.exercises.enumerated().map { (i, ex) -> String in
            let done = (i < session.log.count ? session.log[i] : []).filter { $0.isLogged }.map(\.formatted).joined(separator: ", ")
            return "\(ex.name) [\(done.isEmpty ? "skipped" : done)]"
        }.joined(separator: "; ")
        let prev = history.suffix(3).map { "\($0.date) \($0.plan.sessionType) RPE \($0.fin.map { String($0.rpe) } ?? "?")" }.joined(separator: "; ")

        let msg = """
        The athlete just finished today's session. Give a debrief: EXACTLY 2 short sentences — one on what went well, one on what you'll adjust next time. Plain text, no markdown, max 45 words total. Direct, no hype.

        TODAY (\(session.date), \(session.plan.sessionType)): \(sets)
        Session RPE \(session.fin.map { String($0.rpe) } ?? "?")\(session.fin?.pain.isEmpty == false ? " | pain: \(session.fin!.pain)" : "")\(session.fin?.feedback.isEmpty == false ? " | athlete says: \(session.fin!.feedback)" : "")
        RECENT: \(prev.isEmpty ? "first logged session" : prev)
        """
        return try await callGeminiText(msg, maxTokens: 120, eventType: "ai_debrief")
    }

    static func generateWeeklyReview(_ summary: Stats.WeekSummary) async throws -> String {
        let msg = """
        Write the athlete's weekly review: EXACTLY 2-3 short sentences — how the week went (sessions, progressions) and one concrete nudge for next week. Plain text, no markdown, max 55 words. Direct, no hype.

        THIS WEEK: \(summary.count) sessions
        \(summary.lines)
        LIFTS THAT MOVED UP: \(summary.progressions)
        """
        return try await callGeminiText(msg, maxTokens: 140, eventType: "ai_weekly_review")
    }

    static func generateMonthlyReport(_ s: Stats.MonthSummary) async throws -> String {
        func line(_ label: String, _ cur: Double?, _ prev: Double? = nil, _ unit: String = "") -> String {
            guard let cur else { return "" }
            let priorTxt = prev.map { " (prior month \(fmtKg($0))\(unit))" } ?? ""
            return "\(label): \(fmtKg(cur))\(unit)\(priorTxt)"
        }
        var msg = "Write the athlete's MONTHLY report for \(s.month): EXACTLY 3-5 short sentences, plain text, max 90 words. Cover: how the month went (sessions, volume, lifts that moved), what the recovery data says (sleep/RHR/VO2max trends if present), and ONE concrete focus for next month. Honest and specific, no hype, no markdown.\n\n"
        msg += "FACTS:\n"
        msg += "Sessions: \(s.count)\(s.prevCount > 0 ? " (prior month \(s.prevCount))" : "") — split: \(s.split)\n"
        msg += "Total volume: \(s.volume)kg\(s.prevVolume > 0 ? " (prior \(s.prevVolume)kg)" : "")\n"
        msg += "Lifts that moved up: \(s.progressions)\n"
        for l in [line("Avg session RPE", s.avgRpe), line("Avg sleep", s.sleepAvg, s.sleepPrev, "h"), line("Avg resting HR", s.rhrAvg, s.rhrPrev), line("Avg HRV", s.hrvAvg, nil, "ms"), line("VO2max", s.vo2Avg, s.vo2Prev)] where !l.isEmpty {
            msg += l + "\n"
        }
        if let ws = s.weightStart, let we = s.weightEnd { msg += "Bodyweight: \(fmtKg(ws)) → \(fmtKg(we))kg\n" }
        return try await callGeminiText(msg, maxTokens: 220, eventType: "ai_monthly_report")
    }

    // MARK: - Public entry point: generate with model fallback + retry

    static func generateWorkoutPlan(checkin: Checkin, history: [Session], template: SavedWorkout? = nil, onStatus: ((String) -> Void)? = nil) async throws -> Plan {
        let healthLog = LocalStore.shared.backup.health
        // Errors from models we fell back past — surfaced with the final error so
        // a failing fallback (e.g. a retired model's 404) can't hide the real cause.
        var failures: [String] = []
        for (mi, model) in models.enumerated() {
            do {
                if mi > 0 { onStatus?("Trying \(model)…") }
                return try await callGemini(checkin: checkin, history: history, model: model, healthLog: healthLog, template: template)
            } catch let error as GeminiError {
                if case .noConsent = error { throw error } // no point trying another model
                if case .server = error { throw error }
                if case .overloaded = error, mi < models.count - 1 {
                    failures.append("\(model): overloaded")
                    onStatus?("\(model) is busy — switching model…")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                // rate limited — each model has its own quota, so switch
                // first; only the last model waits and retries
                if case .rateLimited = error, mi < models.count - 1 {
                    failures.append("\(model): rate limited")
                    onStatus?("\(model) is at its limit — switching model…")
                    continue
                }
                if case .rateLimited(let waitSec) = error {
                    for s in stride(from: waitSec, through: 1, by: -1) {
                        onStatus?("Rate limited — retrying in \(s)s…")
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    do {
                        return try await callGemini(checkin: checkin, history: history, model: model, healthLog: healthLog, template: template)
                    } catch let retryErr as GeminiError {
                        if case .overloaded = retryErr, mi < models.count - 1 { continue }
                        if case .rateLimited = retryErr { throw GeminiError.message("Rate limit hit twice. Wait a minute and try again.") }
                        throw retryErr
                    }
                }
                let message = error.errorDescription ?? "\(error)"
                if mi < models.count - 1 {
                    failures.append("\(model): \(message)")
                    continue
                }
                if !failures.isEmpty {
                    throw GeminiError.message("\(model): \(message)\n\nEarlier attempts — \(failures.joined(separator: " · "))")
                }
                throw error
            }
        }
        throw GeminiError.message("Couldn't build today's session. Check Settings for your API key, then try again.")
    }

    // MARK: - Saved workouts: built from a trainer's program, a photo of one, or a description

    private static let workoutsSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "workouts": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING"],
                        "kind": ["type": "STRING", "enum": ["session", "addon"]],
                        "days": ["type": "ARRAY", "items": ["type": "STRING", "enum": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]]],
                        "notes": ["type": "STRING"],
                        "exercises": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "name": ["type": "STRING"], "sets": ["type": "INTEGER"], "reps": ["type": "STRING"],
                                    "weight": ["type": "STRING"], "rest": ["type": "STRING"], "notes": ["type": "STRING"],
                                ],
                                "required": ["name", "sets", "reps"],
                            ],
                        ],
                    ],
                    "required": ["name", "kind", "exercises"],
                ],
            ],
            "message": ["type": "STRING"],
        ],
        "required": ["workouts"],
    ]

    /// Turns what the athlete gave — a trainer's program (text and/or a
    /// JPEG photo of it) or a description — into saved-workout drafts to
    /// review (buildWorkouts in gemini.js). Nothing is saved here.
    static func buildWorkouts(text: String, imageJPEG: Data?, source: String, history: [Session]) async throws -> (workouts: [SavedWorkout], message: String) {
        guard Cloud.shared.aiReady else { throw GeminiError.message("Add your Gemini API key in Settings first — the coach builds workouts with it.") }
        let settings = LocalStore.shared.backup.aiSettings
        var seen = Set<String>()
        let known = history.flatMap { $0.plan.exercises.map { $0.name.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(80)
        let trainer = source == "trainer"
        var msg = "Turn the athlete's input into saved workouts for their training app.\n\n"
        msg += trainer
            ? "This is a program the athlete's personal trainer wrote. Transcribe it faithfully: keep every exercise, set, rep, weight, rest and note exactly as written — never add, drop or 'improve' anything. If something is illegible or ambiguous, make the most likely reading and mention it in \"message\"."
            : "If this is a written program, transcribe it faithfully. If it's a description of what they want (e.g. '20 minutes of core every day', 'upper body with dumbbells, 45 min'), design it: sensible exercises, sets, reps and rest for their goals, equipment and history."
        msg += """


        Rules:
        - One workout per training day. A multi-day program (Day A/B/C, Monday/Wednesday…) becomes several workouts; put the weekdays in "days" ONLY when the input names them (or says "every day" → all seven).
        - kind "addon" for a short routine meant to be added on top of sessions (core finisher, stretching, mobility, warm-up, "every day" habit); otherwise "session".
        - name: short, e.g. "Upper A", "Leg day", "Daily core". Use the input's own day names when it has them.
        - Exercise names: common English gym names. When the exercise is one of the athlete's KNOWN EXERCISES below, use that exact name so their progress links up. Expand abbreviations (DB → Dumbbell, BB → Barbell, RDL → Romanian Deadlift).
        - reps: as written, e.g. "8-10", "12", "45s", "AMRAP". weight: as written, e.g. "20kg", "bodyweight", or "" if none. rest: e.g. "90s", "2 min", or "".
        - notes: tempo, cues or instructions from the input, else "".
        - "message": one short sentence for the athlete — what you built, plus anything you had to guess.

        KNOWN EXERCISES: \(known.isEmpty ? "none yet" : known.joined(separator: ", "))

        """
        let equipment = settings.equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        let goals = settings.goals.trimmingCharacters(in: .whitespacesAndNewlines)
        if !equipment.isEmpty { msg += "EQUIPMENT & LIMITS: \(equipment)\n" }
        if !goals.isEmpty { msg += "GOALS: \(goals)\n" }
        msg += "\nATHLETE'S INPUT:\n\(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(see the attached photo)" : text)"

        var parts: [[String: Any]] = [["text": msg]]
        if let imageJPEG { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": imageJPEG.base64EncodedString()]]) }

        var lastErr: Error = GeminiError.message("no models tried")
        for model in models.prefix(2) {
            var config: [String: Any] = ["maxOutputTokens": 6000, "temperature": trainer ? 0.2 : 0.6, "responseMimeType": "application/json", "responseSchema": workoutsSchema]
            if supportsThinkingLevel(model) { config["thinkingConfig"] = ["thinkingLevel": "low"] }
            do {
                let (out, _, _) = try await post(model: model, systemInstruction: coachRules(), contents: [["role": "user", "parts": parts]], generationConfig: config, timeout: 60)
                guard let data = out.data(using: .utf8), let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw GeminiError.message("The coach's reply couldn't be read — try again.")
                }
                let dayIdx = ["Sun": 0, "Mon": 1, "Tue": 2, "Wed": 3, "Thu": 4, "Fri": 5, "Sat": 6]
                let workouts: [SavedWorkout] = ((obj["workouts"] as? [[String: Any]]) ?? []).compactMap { w in
                    let ex: [SavedWorkout.Exercise] = ((w["exercises"] as? [[String: Any]]) ?? []).map { e in
                        SavedWorkout.Exercise(
                            name: e["name"] as? String ?? "", sets: min(max((e["sets"] as? Int) ?? Int((e["sets"] as? Double) ?? 3), 1), 10),
                            reps: e["reps"] as? String ?? "", weight: e["weight"] as? String ?? "",
                            rest: e["rest"] as? String ?? "", notes: e["notes"] as? String ?? ""
                        )
                    }
                    guard !ex.isEmpty else { return nil }
                    return SavedWorkout(
                        name: w["name"] as? String ?? "Workout", kind: (w["kind"] as? String) == "addon" ? "addon" : "session",
                        source: source, notes: w["notes"] as? String ?? "",
                        days: ((w["days"] as? [String]) ?? []).compactMap { dayIdx[$0] }, exercises: ex
                    )
                }
                let message = obj["message"] as? String ?? ""
                guard !workouts.isEmpty else { throw GeminiError.message(message.isEmpty ? "The coach couldn't find a workout in that — add a bit more detail." : message) }
                LocalStore.shared.logEvent(type: "ai_build_workouts", data: ["model": .string(model), "source": .string(source), "image": .bool(imageJPEG != nil), "workouts": .number(Double(workouts.count))])
                return (workouts, message)
            } catch {
                lastErr = error
            }
        }
        throw lastErr
    }
}
