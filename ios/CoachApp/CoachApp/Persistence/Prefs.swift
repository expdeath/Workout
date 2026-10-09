import Foundation

/// Settings → Alerts & reports switches: account state `prefs` in
/// Firestore, shared with the web app (getPrefs in src/utils/storage.js).
/// All on by default — that's how the app behaved before they existed.
enum Prefs {
    static let defaults: [String: Bool] = [
        "restSound": true,     // beep when the rest timer ends
        "restVibrate": true,   // …and buzz
        "restNotify": true,    // …and notify when the app is in the background
        "keepAwake": true,     // screen stays on during a workout
        "weeklyReview": true,  // Sunday AI review
        "monthlyReport": true, // new-month AI report
        "debrief": true,       // two-sentence AI debrief after each session
    ]

    private static var stored: [String: JSONValue] {
        if case .object(let o)? = Cloud.shared.stateValue("prefs") { return o }
        return [:]
    }

    static func isOn(_ key: String) -> Bool {
        if case .bool(let b)? = stored[key] { return b }
        return defaults[key] ?? true
    }

    static func set(_ key: String, _ on: Bool) {
        var o = stored
        o[key] = .bool(on)
        Cloud.shared.setState("prefs", .object(o))
    }

    /// The raw value, for the backup file.
    static var raw: JSONValue? { Cloud.shared.stateValue("prefs") }
}

/// May the app send data to Google Gemini? Account state `aiConsent`
/// { allowed, at, version }, shared with the web app — asked once per
/// account (AIConsentView, App Store guideline 5.1.2(i)), changeable in
/// Settings → AI Coach. Nothing reaches Gemini without it (Gemini.post).
enum AIConsent {
    static let version = 1

    private static var stored: [String: JSONValue]? {
        if case .object(let o)? = Cloud.shared.stateValue("aiConsent") { return o }
        return nil
    }

    /// The athlete has answered the consent screen (yes or no).
    static var answered: Bool { stored != nil }

    static var allowed: Bool {
        if case .bool(let b)? = stored?["allowed"] { return b }
        return false
    }

    static func set(_ allowed: Bool) {
        Cloud.shared.setState("aiConsent", .object([
            "allowed": .bool(allowed),
            "at": .number((Date().timeIntervalSince1970 * 1000).rounded()),
            "version": .number(Double(version)),
        ]))
    }
}
