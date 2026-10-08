import SwiftUI

// Building blocks shared by the screens — the SwiftUI twins of
// index.css's .card, .label-caps, .tab-header, .pill, .chip and friends.

/// `.card` — raised panel.
struct CoachCard<Content: View>: View {
    var stroke: Color = Theme.border
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(stroke))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// `.label-caps` — small tracked uppercase section label.
struct CardLabel: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View { Text(text).capsLabel(color) }
}

/// Section label with an optional amber action/annotation on the right.
struct SectionHead: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = Theme.amberText
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).capsLabel()
            Spacer()
            if let trailing {
                if let action {
                    Button(action: action) { Text(trailing).capsLabel(trailingColor, size: 12) }
                } else {
                    Text(trailing).capsLabel(trailingColor, size: 12)
                }
            }
        }
    }
}

/// Top bar of the five tab screens: COACH • TITLE, then chat, the
/// notification bell (with an unread dot) and the profile avatar.
struct TabHeader: View {
    @Environment(AppState.self) private var appState
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text("COACH").capsLabel(Theme.amberText, size: 13)
            Circle().fill(Theme.amber.opacity(0.5)).frame(width: 4, height: 4)
            Text(title).font(Theme.head(24, weight: .bold)).textCase(.uppercase).tracking(1).foregroundStyle(Theme.text)
            Spacer()
            IconButton(icon: "bubble.left", label: "Ask the coach") { appState.chatOpen = true }
            ZStack(alignment: .topTrailing) {
                IconButton(icon: "bell", label: appState.unreadNotifications > 0 ? "Notifications, \(appState.unreadNotifications) new" : "Notifications") {
                    appState.sheet = .notifications
                }
                if appState.unreadNotifications > 0 {
                    Circle().fill(Theme.amber).frame(width: 7, height: 7).offset(x: -11, y: 11).allowsHitTesting(false)
                }
            }
            Button { appState.sheet = .profile } label: { Avatar(name: appState.displayName, size: 32) }
                .accessibilityLabel("Profile")
        }
        .padding(.bottom, 6)
    }
}

/// Initials in an amber circle.
struct Avatar: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(Theme.head(size * 0.45, weight: .bold))
            .foregroundStyle(Theme.onAmber)
            .frame(width: size, height: size)
            .background(Theme.amber)
            .clipShape(Circle())
    }
}

/// Pushed screens: back chevron, uppercase title, optional trailing icon.
struct ScreenHeader: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var trailing: (icon: String, label: String, action: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let onBack { BackButton(action: onBack) }
            Text(title).font(Theme.head(28, weight: .bold)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
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
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 40, height: 44)
        }
        .accessibilityLabel(label)
    }
}

/// Rounded-square icon well (rows, tiles, record lines).
struct IconWell: View {
    let icon: String
    var tint: Color = Theme.amberText
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Theme.bgHigh)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

/// `.status-pill` — dot + caps text on a tinted capsule.
struct StatusPill: View {
    let text: String
    var color: Color = Theme.green
    var dot = true
    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text).capsLabel(color, size: 12)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// Centered big number over a caps label (Today's three stats).
struct StatBlock: View {
    let value: String
    let label: String
    var color: Color = Theme.text
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(Theme.head(38, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).capsLabel(Theme.muted, size: 11).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// Thin rounded progress bar.
struct ProgressLine: View {
    let fraction: Double
    var color: Color = Theme.amber
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bgInput)
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// 8 WEEKS · 3 MONTHS · YEAR style segmented switch.
struct SegmentedTabs: View {
    let options: [(value: String, label: String)]
    @Binding var value: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let on = opt.value == value
                Button { value = opt.value } label: {
                    Text(opt.label).capsLabel(on ? Theme.onAmber : Theme.muted, size: 12)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(on ? Theme.amber : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm - 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm + 2))
    }
}

/// Square launcher tile: icon well over a caps label.
struct LaunchTile: View {
    let icon: String
    let label: String
    var tint: Color = Theme.amberText
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 36, height: 36).background(Theme.bgHigh).clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                Text(label).capsLabel(Theme.textBody, size: 11).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
    }
}

/// `.chip` — small pill button.
struct Chip: View {
    let title: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).capsLabel(on ? Theme.onAmber : Theme.textBody, size: 12)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Theme.amber : Theme.bgPill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A grouped settings row: icon well, title + subtitle, value, chevron.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    var tint: Color = Theme.amberText
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let row = HStack(spacing: 14) {
            IconWell(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(16, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.meta(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailing
            if action != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(icon: String, tint: Color = Theme.amberText, title: String, subtitle: String? = nil, action: (() -> Void)? = nil) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, action: action) { EmptyView() }
    }
}

/// A rounded group of SettingsRows with inset hairlines between them.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            _VariadicView.Tree(DividedLayout()) { content }
        }
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private struct DividedLayout: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            ForEach(children) { child in
                child
                if child.id != children.last?.id {
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 64)
                }
            }
        }
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
                .font(Theme.body(15))
                .foregroundStyle(user ? Theme.onAmber : Theme.textBody)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(user ? Theme.amber : Theme.bgCard)
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
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onAmber)
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
            .font(Theme.data(19))
            .frame(maxWidth: 76)
            .padding(.vertical, 7)
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
