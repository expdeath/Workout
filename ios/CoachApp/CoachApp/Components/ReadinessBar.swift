import SwiftUI

/// Ports src/components/ReadinessBar.jsx — a readiness meter, teal ≥70,
/// amber ≥45, red below. One thin bar: the number carries the meaning.
struct ReadinessBar: View {
    let value: Int
    let label: String

    private var color: Color { value >= 70 ? Theme.green : value >= 45 ? Theme.amber : Theme.red }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).capsLabel().fixedSize()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.bgInput)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(max(Double(value) / 100, 0), 1))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.3), value: value)
            Text("\(value)").font(Theme.head(26, weight: .bold)).foregroundStyle(color)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityIdentifier("readiness")
    }
}
