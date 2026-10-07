import SwiftUI

/// Ports src/screens/Finish.jsx — 20-second post-session log: session
/// RPE, pain, too easy/hard, with a PR celebration when today beat an
/// all-time record. Save → AppState.finishSession (Firestore + debrief).
struct FinishView: View {
    @Environment(AppState.self) private var appState
    @State private var confetti = false
    @State private var saving = false

    private var fin: Binding<FinishInfo> {
        Binding(get: { appState.fin }, set: { appState.fin = $0 })
    }

    /// all-time records beaten today, vs everything before this session
    private var prs: [PRRecord] {
        guard let t = appState.todayPlan else { return [] }
        return Stats.detectPRs(t, appState.history.filter { $0.id != t.id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("Back") { appState.screen = .workout }
                        .font(Theme.head(16, weight: .semibold)).textCase(.uppercase).tracking(1.3)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding(.bottom, 14)

                Text("Log it. 20 seconds.").font(Theme.head(28, weight: .bold))

                if !prs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🏆 New personal record\(prs.count > 1 ? "s" : "")")
                            .font(Theme.head(17, weight: .bold)).foregroundStyle(Theme.amber)
                        ForEach(prs, id: \.self) { p in
                            Text("\(p.name) — \(p.kind == "weight" ? "heaviest set" : "est. 1RM") \(Helpers.fmtKg(p.from)) → \(Helpers.fmtKg(p.to))kg")
                                .font(Theme.mono(13))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.amberBg)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 14)
                }

                QLabel(text: "Overall session RPE", value: "\(appState.fin.rpe)/10")
                Slider(value: Binding(get: { Double(appState.fin.rpe) }, set: { appState.fin.rpe = Int($0) }), in: 1...10, step: 1)
                    .tint(Theme.amber)

                QLabel(text: "Any pain or discomfort?")
                TextField("", text: fin.pain, prompt: Text("e.g. none / left shoulder on incline press").foregroundStyle(Theme.dim))
                    .coachInput()

                QLabel(text: "Too easy / too hard?")
                TextField("", text: fin.feedback, prompt: Text("e.g. leg press felt light, curls brutal").foregroundStyle(Theme.dim))
                    .coachInput()

                Button(saving ? "Saving…" : "Save session") {
                    saving = true
                    Task { await appState.finishSession() }
                }
                .buttonStyle(BigButtonStyle())
                .disabled(saving)
                .padding(.top, 28)

                Text("Weights and reps you logged per set are saved automatically. This feeds tomorrow's plan.")
                    .font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coachScreen()
        .overlay { if confetti { ConfettiBurst().allowsHitTesting(false) } }
        .onAppear {
            guard !prs.isEmpty else { return }
            confetti = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { confetti = false }
        }
    }
}

extension PRRecord: Hashable {
    func hash(into h: inout Hasher) { h.combine(name); h.combine(kind) }
}

/// One burst of falling pieces — the web app's .confetti-burst.
private struct ConfettiBurst: View {
    private static let colors: [Color] = [Theme.amber, Theme.teal, Theme.red, Color(hex: 0x7EA6F5), Color(hex: 0xE4C1F9)]
    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<28, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.colors[i % Self.colors.count])
                    .frame(width: 8, height: 12)
                    .rotationEffect(.degrees(fall ? Double(i * 47 % 360) + 360 : 0))
                    .position(x: geo.size.width * CGFloat((i * 37 + 13) % 100) / 100,
                              y: fall ? geo.size.height + 20 : -20)
                    .animation(.easeIn(duration: 2 + Double((i * 13) % 10) / 10).delay(Double(i % 7) * 0.12), value: fall)
            }
        }
        .ignoresSafeArea()
        .onAppear { fall = true }
    }
}
