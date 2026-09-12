import SwiftUI

/// Ports src/components/QuickCardioSheet.jsx — a run/ride/walk/hike
/// logged straight to history in a few taps, bypassing check-in + AI
/// entirely.
struct QuickCardioSheet: View {
    let kind: String
    var onSave: (_ kind: String, _ time: String, _ dist: String, _ rpe: Int, _ date: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = ""
    @State private var dist = ""
    @State private var rpe = 6
    @State private var daysAgo = "0" // forgot to log it yesterday → backdate

    private var meta: (label: String, verb: String, icon: String) {
        switch kind {
        case "run": return ("Log a run", "run", "🏃")
        case "cycle": return ("Log a ride", "ride", "🚴")
        case "walk": return ("Log a walk", "walk", "🚶")
        case "hike": return ("Log a hike", "hike", "🥾")
        default: return ("Log a run", "run", "🏃")
        }
    }

    private var canSave: Bool { !time.isEmpty || !dist.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Theme.border).frame(width: 40, height: 4).frame(maxWidth: .infinity)

            Text(meta.label)
                .font(Theme.mono(13, weight: .medium))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)

            Text("Saved straight to your log — no check-in, no AI plan.")
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.muted)

            SegGroup(options: [("0", "Today"), ("1", "Yesterday"), ("2", "2 days ago")], value: $daysAgo)

            HStack(spacing: 8) {
                TextField("min", text: $time)
                    .keyboardType(.decimalPad)
                    .onChange(of: time) { _, v in time = Helpers.cleanTime(v) }
                    .quickCardioField()
                Text("min").font(Theme.mono(13)).foregroundStyle(Theme.dim)
                TextField("km", text: $dist)
                    .keyboardType(.decimalPad)
                    .onChange(of: dist) { _, v in dist = Helpers.cleanDist(v) }
                    .quickCardioField()
                Text("km (optional)").font(Theme.mono(13)).foregroundStyle(Theme.dim)
            }

            HStack {
                Text("Effort").font(Theme.head(13, weight: .semibold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(rpe)/10").font(Theme.mono(15)).foregroundStyle(Theme.amber)
            }
            Slider(value: Binding(get: { Double(rpe) }, set: { rpe = Int($0) }), in: 1...10, step: 1)
                .tint(Theme.amber)

            Button {
                guard canSave else { return }
                onSave(kind, time, dist, rpe, Helpers.daysAgoStr(Int(daysAgo) ?? 0))
                dismiss()
            } label: {
                Text("\(meta.icon) Save \(meta.verb)")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .foregroundStyle(Theme.bg)
            .background(canSave ? Theme.teal : Theme.teal.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .disabled(!canSave)
        }
        .padding(16)
        .background(Theme.bgCard)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
        .coachScreen()
    }
}

private struct QuickCardioFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.mono(15))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.text)
            .padding(10)
            .frame(width: 78)
            .background(Theme.bgInput)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(Theme.borderDim))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

private extension View {
    func quickCardioField() -> some View { modifier(QuickCardioFieldStyle()) }
}
