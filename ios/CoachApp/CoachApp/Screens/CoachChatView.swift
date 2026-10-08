import SwiftUI

/// Ports src/screens/Coach.jsx — the coach chat as a bottom sheet,
/// reachable from any screen. Today's chat is account state in Firestore
/// (`chat-<date>`, same key and shape as the web app), so a conversation
/// started on the phone continues on the web and vice versa.
struct CoachChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Gemini.ChatMessage] = []
    @State private var input = ""
    @State private var busy = false
    @State private var error = ""

    private static let prefix = "chat-"
    private static let starters = ["Shoulder feels off — what do I swap?", "Too tired for legs. Alternatives?", "How heavy should warm-up sets be?"]
    private var key: String { Self.prefix + Helpers.todayStr() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Coach").font(Theme.head(26, weight: .bold))
                Spacer()
                IconButton(icon: "xmark", label: "Close chat") { dismiss() }
            }
            .padding(.horizontal, 16).padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty {
                            // tap a starter instead of reading a paragraph of examples
                            ForEach(Self.starters, id: \.self) { q in
                                Button { input = q } label: {
                                    Text(q).font(Theme.body(14.5)).foregroundStyle(Theme.textBody)
                                        .padding(.horizontal, 13).padding(.vertical, 10)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderDim))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                            ChatBubble(text: m.text, user: m.role == "user")
                        }
                        if busy { ChatBubble(text: "…") }
                        if !error.isEmpty { ErrorBox(text: error) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
                .onChange(of: busy) { _, _ in withAnimation { proxy.scrollTo("end") } }
            }

            ChatInputRow(text: $input, placeholder: "Ask the coach…", busy: busy, send: send)
                .padding(16)
        }
        .coachScreen()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { messages = load() }
    }

    // ── Persistence: state chat-<date>, [{ role, text }] like the web ──

    private func load() -> [Gemini.ChatMessage] {
        guard case .array(let a)? = Cloud.shared.stateValue(key) else { return [] }
        return a.compactMap {
            guard case .object(let o) = $0, case .string(let role)? = o["role"], case .string(let text)? = o["text"] else { return nil }
            return Gemini.ChatMessage(role: role, text: text)
        }
    }

    private func save(_ msgs: [Gemini.ChatMessage]) {
        // today's chat only — yesterday's questions rarely matter tomorrow
        for k in Cloud.shared.stateKeys() where k.hasPrefix(Self.prefix) && k != key { Cloud.shared.setState(k, nil) }
        Cloud.shared.setState(key, .array(msgs.suffix(30).map { .object(["role": .string($0.role), "text": .string($0.text)]) }))
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        let next = messages + [Gemini.ChatMessage(role: "user", text: text)]
        messages = next
        save(next)
        input = ""
        error = ""
        busy = true
        Task {
            do {
                let reply = try await Gemini.askCoach(messages: next, history: appState.history, todayPlan: appState.todayPlan,
                                                      healthLog: LocalStore.shared.backup.health)
                let done = next + [Gemini.ChatMessage(role: "coach", text: reply)]
                messages = done
                save(done)
            } catch {
                self.error = HistoryDetailView.chatError(error)
            }
            busy = false
        }
    }
}
