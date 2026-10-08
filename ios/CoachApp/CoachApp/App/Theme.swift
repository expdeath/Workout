import SwiftUI

/// Visual design system — the same tokens as the :root custom properties
/// in src/index.css, so the native app and the website look identical.
/// Dark only (no light variant), like the web app.
enum Theme {
    // MARK: Colors

    /// page background (surface-base)
    static let bg = Color(hex: 0x0B0F17)
    /// raised card (surface-elevated)
    static let bgCard = Color(hex: 0x131B2E)
    /// inset fields and wells (surface-container-lowest)
    static let bgInput = Color(hex: 0x0A0E16)
    /// tiles and rows inside a card (surface-container-low)
    static let bgPill = Color(hex: 0x1A1F2B)
    /// pressed / selected surface (surface-container-high)
    static let bgHigh = Color(hex: 0x262A33)
    static let border = Color.white.opacity(0.07)
    static let borderDim = Color(hex: 0x2B3140)
    static let text = Color(hex: 0xF8FAFC)
    static let textBody = Color(hex: 0xDFE2EE)
    static let muted = Color(hex: 0x8391A7)
    static let dim = Color(hex: 0x4E5869)
    /// brand amber (primary-container) and its lighter tint for text
    static let amber = Color(hex: 0xF59E0B)
    static let amberText = Color(hex: 0xFBBF24)
    static let amberBg = Color(hex: 0xF59E0B).opacity(0.12)
    /// success / recovery green (tertiary)
    static let green = Color(hex: 0x56E5A9)
    static let greenBg = Color(hex: 0x56E5A9).opacity(0.12)
    static let red = Color(hex: 0xF26D5B)
    static let redBg = Color(hex: 0xF26D5B).opacity(0.12)
    /// text on an amber button
    static let onAmber = Color(hex: 0x080B11)
    // chart series: darker steps of the brand amber/green
    static let chartAmber = Color(hex: 0xD48A0A)
    static let chartGreen = Color(hex: 0x30C88F)

    // MARK: Fonts
    // --font-head: Barlow Condensed (titles, numbers, caps labels)
    // --font-body: Space Grotesk (everything you read)

    static func head(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name = weight == .bold || weight == .heavy || weight == .black ? "BarlowCondensed-Bold"
            : (weight == .medium || weight == .regular ? "BarlowCondensed-Medium" : "BarlowCondensed-SemiBold")
        return .custom(name, size: size)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .bold || weight == .heavy || weight == .semibold ? "SpaceGrotesk-Bold"
            : (weight == .medium ? "SpaceGrotesk-Medium" : "SpaceGrotesk-Regular")
        return .custom(name, size: size)
    }

    /// Secondary text — dates, set summaries, captions — with tabular
    /// digits so numbers line up.
    static func meta(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        body(size, weight: weight).monospacedDigit()
    }

    /// Numbers you type or watch tick (set inputs, the rest timer).
    static func data(_ size: CGFloat) -> Font {
        head(size, weight: .bold).monospacedDigit()
    }

    // MARK: Reusable metrics

    static let radius: CGFloat = 12
    static let radiusSm: CGFloat = 9
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

/// `.big-btn` — the amber, full-width, uppercase CTA with a soft glow.
struct BigButtonStyle: ButtonStyle {
    var danger: Bool = false
    var icon: String? = nil
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
            configuration.label
        }
        .font(Theme.head(20, weight: .bold))
        .textCase(.uppercase)
        .tracking(1.4)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .foregroundStyle(danger ? .white : Theme.onAmber)
        .background(danger ? Theme.red : Theme.amber)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .shadow(color: (danger ? Theme.red : Theme.amber).opacity(0.28), radius: 14, y: 2)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A quieter, outlined secondary button (Quick log, Sign out…).
struct OutlineButtonStyle: ButtonStyle {
    var color: Color = Theme.amber
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.head(15, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(color.opacity(0.55)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// The app's single dark background + default text color — call once
    /// at each screen's root.
    func coachScreen() -> some View {
        self
            .foregroundStyle(Theme.text)
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.amber)
    }

    /// Small tracked uppercase label (`.label-caps`).
    func capsLabel(_ color: Color = Theme.muted, size: CGFloat = 13) -> some View {
        self.font(Theme.head(size, weight: .bold)).textCase(.uppercase).tracking(1.6).foregroundStyle(color)
    }
}
