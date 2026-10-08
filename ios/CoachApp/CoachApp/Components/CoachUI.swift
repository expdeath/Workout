import SwiftUI

// Small building blocks shared by the screens — the SwiftUI versions of
// index.css's .card, .card__label, .chip, .header and .chat-bubble.

/// `.card` — dark rounded panel.
struct CoachCard<Content: View>: View {
    var stroke: Color = Theme.border
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// `.card__label` — small section label, sentence case.
struct CardLabel: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text).font(Theme.body(13.5, weight: .semibold)).foregroundStyle(color)
    }
}

/// `.header` — optional back chevron, large left-aligned title,
/// optional trailing icon button.
struct ScreenHeader: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var trailing: (icon: String, label: String, action: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let onBack { BackButton(action: onBack) }
            Text(title).font(Theme.head(30, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            if let trailing {
                IconButton(icon: trailing.icon, label: trailing.label, action: trailing.action)
            }
        }
        .padding(.bottom, 8)
    }
}

/// ‹ — the one back affordance every pushed screen uses.
struct BackButton: View {
    var label = "Back"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 44, alignment: .leading)
        }
        .accessibilityLabel(label)
    }
}

/// A 44pt tap target around an SF Symbol.
struct IconButton: View {
    let icon: String
    let label: String
    var color: Color = Theme.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}

/// `.chip` — small pill button.
struct Chip: View {
    let title: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(Theme.body(13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Theme.bg : Theme.text)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(on ? Theme.teal : Theme.bgPill)
            .clipShape(Capsule())
    }
}

/// `.chat-bubble` (coach, left) / `.chat-bubble--user` (right).
struct ChatBubble: View {
    let text: String
    var user = false
    var body: some View {
        HStack {
            if user { Spacer(minLength: 40) }
            Text(text)
                .font(Theme.body(14.5))
                .foregroundStyle(user ? Theme.bg : Theme.textBody)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(user ? Theme.teal : Theme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            if !user { Spacer(minLength: 40) }
        }
    }
}

/// Text input + ↑ send button, used by both chats.
struct ChatInputRow: View {
    @Binding var text: String
    var placeholder: String
    var busy: Bool
    var send: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(get: { text }, set: { text = String($0.prefix(500)) }),
                      prompt: Text(placeholder).foregroundStyle(Theme.dim))
                .coachInput()
                .onSubmit(send)
            Button(action: send) {
                Text("↑").font(Theme.head(20, weight: .bold)).foregroundStyle(Theme.bg)
                    .frame(width: 44, height: 44).background(Theme.amber).clipShape(Circle())
            }
            .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(busy || text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .accessibilityLabel("Send")
        }
    }
}

/// Number field used for set inputs (kg / reps / min / km).
struct SetField: View {
    let value: String
    let placeholder: String
    var decimal = true
    let set: (String) -> Void

    var body: some View {
        TextField("", text: Binding(get: { value }, set: set), prompt: Text(placeholder).foregroundStyle(Theme.dim))
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(Theme.mono(15))
            .frame(maxWidth: 76)
            .padding(.vertical, 8)
            .background(Theme.bgInput)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(Theme.borderDim))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

/// Long coach text clamped to a few lines; tap to read the rest.
struct ExpandableText: View {
    let text: String
    var lines = 4
    @State private var open = false
    var body: some View {
        Text(text)
            .font(Theme.body(14.5)).foregroundStyle(Theme.textBody)
            .lineLimit(open ? nil : lines)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } }
    }
}
