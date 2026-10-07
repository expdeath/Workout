import Foundation

extension Stats {
    struct GoalProgress: Equatable {
        var text: String
        var current: Double?
        var target: Double?
        var unit: String
    }

    /// Goals (one per line, Settings → AI Coach) → progress, like
    /// goalProgress() in src/utils/stats.js: "4 sessions a week" tracks
    /// this week's count; "Bench Press 80kg" tracks the all-time best set
    /// of the matching exercise; anything else is listed without a bar.
    static func goalProgress(_ history: [Session], _ goalsText: String) -> [GoalProgress] {
        let lines = goalsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        let records = prRecords(history)
        let thisWeek = weekStats(history).thisWeek
        return lines.map { text in
            if let g = firstMatch(#"(\d+)\s*(?:x|sessions?|days?)\s*(?:a|per|/)\s*week"#, in: text),
               let n = (g[safe: 1] ?? nil).flatMap(Double.init) {
                return GoalProgress(text: text, current: Double(thisWeek), target: n, unit: " this week")
            }
            if let g = firstMatch(#"^(.*?)\s+(\d+(?:\.\d+)?)\s*kg\b"#, in: text),
               let namePart = (g[safe: 1] ?? nil)?.trimmingCharacters(in: .whitespaces).lowercased(),
               let target = (g[safe: 2] ?? nil).flatMap(Double.init),
               let rec = records.first(where: { r in
                   r.weight != nil && (r.name.lowercased().contains(namePart) || namePart.contains(r.name.lowercased()))
               }), let w = rec.weight {
                return GoalProgress(text: text, current: w.w, target: target, unit: "kg")
            }
            return GoalProgress(text: text, current: nil, target: nil, unit: "")
        }
    }
}
