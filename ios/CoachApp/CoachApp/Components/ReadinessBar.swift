import SwiftUI

/// Ports src/components/ReadinessBar.jsx — a 20-segment readiness meter,
/// teal ≥70, amber ≥45, red below.
struct ReadinessBar: View {
    let value: Int
    let label: String

    private let segs = 20
    private var color: Color { value >= 70 ? Theme.teal : value >= 45 ? Theme.amber : Theme.red }

    var body: some View {
        let filled = Int((Double(value) / 100 * Double(segs)).rounded())
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.head(13, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(value)").font(Theme.mono(22)).foregroundStyle(color)
            }
            HStack(spacing: 3) {
                ForEach(0..<segs, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < filled ? color.opacity(0.5 + 0.5 * Double(i) / Double(segs)) : Theme.border)
                        .frame(height: 22)
                }
            }
            .animation(.easeOut(duration: 0.3), value: filled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityIdentifier("readiness")
    }
}
