import SwiftUI

/// Ports src/screens/HistoryDetail.jsx — one logged session in full,
/// with a coach chat scoped to just it (ephemeral, like the web app's).
struct HistoryDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var messages: [Gemini.ChatMessage] = []
    @State private var input = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        if let s = appState.detailSession {
            content(s)
        } else {
            Color.clear.coachScreen().onAppear { appState.screen = .history }
        }
    }

    private func content(_ s: Session) -> some View {
        let health = LocalStore.shared.backup.health
        let kcal = Calories.estimate(s, bodyKg: Calories.latestBodyWeightKg(health))
        let exercises = s.plan.exercises.enumerated().compactMap { exI, ex -> (String, [SetLog])? in
            let sets = (s.log[safe: exI] ?? []).filter(\.isLogged)
            return sets.isEmpty ? nil : (ex.name, sets)
        }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ScreenHeader(back: "Log", title: s.plan.sessionType.uppercased(), onBack: { appState.screen = .history })

                    Text("\(Helpers.fmtDate(s.date))\(s.durationMin.map { " · \($0) min" } ?? "")\(kcal > 0 ? " · ~\(kcal.formatted()) kcal" : "")")
                        .font(Theme.mono(12.5)).foregroundStyle(Theme.muted)
                    if let fin = s.fin {
                        Text("RPE \(fin.rpe)/10\(fin.pain.isEmpty ? "" : " · pain: \(fin.pain)")")
                            .font(Theme.mono(13)).foregroundStyle(Theme.amber)
                    }

                    ForEach(exercises, id: \.0) { name, sets in
                        CoachCard {
                            Text(name).font(Theme.head(16, weight: .bold))
                            ForEach(Array(sets.enumerated()), id: \.offset) { i, st in
                                Text("Set \(i + 1): \(st.formatted)").font(Theme.mono(13)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if exercises.isEmpty {
                        Text(s.fin?.feedback.isEmpty == false ? s.fin!.feedback : "No sets were logged for this session.")
                            .font(Theme.body(13.5)).foregroundStyle(Theme.muted)
                    } else if let fb = s.fin?.feedback, !fb.isEmpty {
                        Text("\"\(fb)\"").font(Theme.body(13.5)).foregroundStyle(Theme.muted)
                    }

                    if let d = s.debrief, !d.isEmpty {
                        CoachCard {
                            CardLabel(text: "Coach debrief")
                            Text(d).font(Theme.body(14.5)).foregroundStyle(Theme.textBody)
                        }
                    }

                    Divider().overlay(Theme.border).padding(.top, 12)
                    QLabel(text: "Ask about this session")

                    if messages.isEmpty {
                        ChatBubble(text: "Ask me anything about this \(s.plan.sessionType) session.")
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                        ChatBubble(text: m.text, user: m.role == "user")
                    }
                    if busy { ChatBubble(text: "…") }
                    if !error.isEmpty { ErrorBox(text: error) }

                    ChatInputRow(text: $input, placeholder: "Ask about this session…", busy: busy) { send(s) }
                        .padding(.top, 4)
                        .id("input")
                    Spacer().frame(height: 24)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("input", anchor: .bottom) } }
        }
        .coachScreen()
    }

    private func send(_ s: Session) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        let next = messages + [Gemini.ChatMessage(role: "user", text: text)]
        messages = next
        input = ""
        error = ""
        busy = true
        Task {
            do {
                let reply = try await Gemini.askCoach(messages: next, history: appState.history,
                                                      healthLog: LocalStore.shared.backup.health, focusSession: s)
                messages = next + [Gemini.ChatMessage(role: "coach", text: reply)]
            } catch {
                self.error = Self.chatError(error)
            }
            busy = false
        }
    }

    /// Same wording as the web chats.
    static func chatError(_ e: Error) -> String {
        let m = e.localizedDescription
        return m.range(of: "status|empty", options: [.regularExpression, .caseInsensitive]) != nil
            ? "The coach didn’t answer — check your API key in Settings, then try again."
            : (m.isEmpty ? "The coach is unreachable — try again." : m)
    }
}
