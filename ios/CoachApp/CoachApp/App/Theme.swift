import SwiftUI

/// Visual design system — ports the CSS custom properties in
/// src/index.css exactly, so the native app matches the website's
/// look rather than falling back to default SwiftUI system styling.
/// The web app is dark-themed only (no light variant), so this app
/// commits to the same: colors are defined once, not swapped per
/// color scheme.
enum Theme {
    // MARK: Colors (:root custom properties)

    static let bg = Color(hex: 0x10141C)
    static let bgCard = Color(hex: 0x161C28)
    static let bgInput = Color(hex: 0x10141C)
    static let bgPill = Color(hex: 0x1A2130)
    static let border = Color(hex: 0x232B3A)
    static let borderDim = Color(hex: 0x2A3242)
    static let text = Color(hex: 0xE8ECF4)
    static let textBody = Color(hex: 0xC7CEDC)
    static let muted = Color(hex: 0x8A93A6)
    static let dim = Color(hex: 0x4A5468)
    static let amber = Color(hex: 0xF5A623)
    static let amberBg = Color(hex: 0x241F14)
    static let teal = Color(hex: 0x39D0B8)
    static let tealBg = Color(hex: 0x0F2B26)
    static let red = Color(hex: 0xF26D5B)
    static let redBg = Color(hex: 0x241614)
    static let chartAmber = Color(hex: 0xC4790F)
    static let chartTeal = Color(hex: 0x219B84)

    // MARK: Fonts
    // --font-head: Barlow Condensed · --font-mono: IBM Plex Mono
    // --font-body: Archivo (falls back to system — see Resources/Fonts
    // for why only head/mono are bundled).

    static func head(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name = weight == .bold ? "BarlowCondensed-Bold" : (weight == .medium ? "BarlowCondensed-Medium" : "BarlowCondensed-SemiBold")
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: Reusable metrics

    static let radius: CGFloat = 10
    static let radiusSm: CGFloat = 8
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// `.big-btn` — the amber, full-width, uppercase-tracked CTA used
/// throughout the web app (Login, CheckIn, Finish, ...).
struct BigButtonStyle: ButtonStyle {
    var danger: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.head(19, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(danger ? .white : Theme.bg)
            .background(danger ? Theme.red : Theme.amber)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension View {
    /// Applies the app's single dark background + default text color,
    /// mirroring `.app`/`body` in index.css — call once at each
    /// screen's root.
    func coachScreen() -> some View {
        self
            .foregroundStyle(Theme.text)
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.teal)
    }
}
