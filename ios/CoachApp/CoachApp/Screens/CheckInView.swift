import SwiftUI
import UIKit

/// Ports src/screens/CheckIn.jsx — the 60-second pre-session check-in.
/// Pre-set for a normal day (AppState.buildDefaultCheckin); submitting
/// hands AppState.ci to the AI via generateWorkout.
struct CheckInView: View {
    @Environment(AppState.self) private var appState
    // auto-open the extras when the Watch inbox pre-filled health data
    @State private var showMore = false
    @State private var autoFilled = false

    private var ci: Binding<Checkin> {
        Binding(get: { appState.ci }, set: { appState.ci = $0 })
    }

    private var health: Binding<String> {
        Binding(get: { appState.ci.health ?? "" }, set: { appState.ci.health = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Text("Pre-set for a normal day. Only tap what's different — then build.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)

                QLabel(text: "Energy", value: "\(appState.ci.energy)/10")
                Slider(
                    value: Binding(get: { Double(appState.ci.energy) }, set: { appState.ci.energy = Int($0) }),
                    in: 1...10, step: 1
                )
                .tint(Theme.amber)

                QLabel(text: "Sleep last night")
                SegGroup(options: [("Great", "Great"), ("OK", "OK"), ("Poor", "Poor")], value: ci.sleep)

                QLabel(text: "Soreness")
                SegGroup(options: [("None", "None"), ("Light", "Light"), ("Very sore", "Very sore")], value: ci.soreness)
                if appState.ci.soreness != "None" {
                    TextField("", text: ci.soreAreas, prompt: prompt("Where? e.g. chest, quads"))
                        .coachInput()
                        .padding(.top, 10)
                }

                QLabel(text: "Gym time (walk not included)")
                SegGroup(options: [("30", "30m"), ("45", "45m"), ("60", "60m"), ("75", "75m+")], value: ci.timeAvail)

                moreToggle
                if showMore { moreDetails }

                ReadinessBar(value: Helpers.quickReadiness(appState.ci), label: "Quick readiness estimate")
                    .padding(.top, 24)

                if !appState.error.isEmpty {
                    ErrorBox(text: appState.error).padding(.top, 14)
                }

                Button("Build today's session") {
                    Task { await appState.generateWorkout(appState.ci) }
                }
                .buttonStyle(BigButtonStyle())
                .padding(.top, 18)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
        .onAppear {
            autoFilled = !(appState.ci.health ?? "").isEmpty
            showMore = autoFilled
        }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            Text("CHECK-IN")
                .font(Theme.head(18, weight: .bold))
                .tracking(4)
                .foregroundStyle(Theme.amber)
            HStack {
                Button("Cancel") { appState.screen = .home }
                    .font(Theme.head(16, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(.bottom, 14)
    }

    private var moreToggle: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showMore.toggle() }
            } label: {
                HStack {
                    Text(showMore ? "− Hide more details" : "+ More details — back, vibe, health data")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .font(Theme.head(15, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 13)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private var moreDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            Pill(
                on: appState.ci.backTight, warn: true,
                text: appState.ci.backTight ? "✓ Lower back tight today — coach will adapt" : "Lower back tight today?"
            ) { appState.ci.backTight.toggle() }

            if let gap = appState.muscleGap {
                let tip = Stats.muscleFixTips[gap.group] ?? ""
                Pill(
                    on: !appState.ci.prioritizeMuscle.isEmpty,
                    text: appState.ci.prioritizeMuscle.isEmpty
                        ? "\(gap.group) hasn't been trained in \(gap.lastDaysAgo) days — add \(tip) today?"
                        : "✓ Prioritizing \(gap.group) today"
                ) {
                    appState.ci.prioritizeMuscle = appState.ci.prioritizeMuscle.isEmpty ? gap.group : ""
                }
                .padding(.top, 10)
            }

            QLabel(text: "Today's vibe").padding(.top, -4)
            SegGroup(
                options: [
                    ("", "Coach's call"), ("lift", "Lift"), ("cardio", "Cardio"),
                    ("core", "Core"), ("stretch", "Stretch"), ("surprise", "🎲 Surprise me"),
                ],
                value: ci.wish,
                columns: 3
            )

            QLabel(text: "Health data").padding(.top, -4)
            if autoFilled, !(appState.ci.health ?? "").isEmpty {
                Text("⌚ Watch data loaded — the coach will read it")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.teal)
                    .padding(.bottom, 8)
            } else {
                Pill(on: false, text: "⌚ Paste Watch data from clipboard", action: pasteHealth)
                    .padding(.bottom, 8)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: health)
                    .font(Theme.body(14.5))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 100)
                    .padding(8)
                if (appState.ci.health ?? "").isEmpty {
                    Text("Paste anything — sleep, HRV, resting HR, steps.\ne.g. Sleep 6h40m · HRV 48 · RHR 58")
                        .font(Theme.body(14.5))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.bgInput)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.borderDim))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))

            QLabel(text: "Body weight today (optional)").padding(.top, -4)
            TextField("", text: ci.bodyKg, prompt: prompt("kg — one number a day, charted in Stats"))
                .keyboardType(.decimalPad)
                .onChange(of: appState.ci.bodyKg) { _, v in
                    let clean = String(v.filter { $0.isNumber || $0 == "." }.prefix(6))
                    if clean != v { appState.ci.bodyKg = clean }
                }
                .coachInput()

            TextField("", text: ci.notes, prompt: prompt("Anything else? (injury, plans — optional)"))
                .coachInput()
                .padding(.top, 10)

            Text("Tip: paste today's Apple Health numbers — the coach reads them.")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.dim)
                .padding(.top, 10)
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private func prompt(_ s: String) -> Text {
        Text(s).foregroundStyle(Theme.dim)
    }

    /// Mirrors pasteHealth() + storeTodaysHealth(): today's health row
    /// keeps the raw text so Stats/AI context see it on later plans too.
    private func pasteHealth() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let t = String(text.prefix(2000))
        LocalStore.shared.mergeHealth(HealthRow(date: Helpers.todayStr(), raw: t, receivedAt: Date().timeIntervalSince1970 * 1000))
        LocalStore.shared.logEvent(type: "health_pasted", data: ["chars": .number(Double(t.count))])
        appState.ci.health = t
        autoFilled = true
    }
}

#Preview {
    CheckInView().environment(AppState())
}
