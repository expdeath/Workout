import SwiftUI

// Small form building blocks shared by the check-in, finish, and
// settings screens — each ports one CSS class from src/index.css.

/// `.q-label` (+ `.q-label--row` with a `.q-label__value` on the right).
struct QLabel: View {
    let text: String
    var value: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Theme.head(13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.8)
                .foregroundStyle(Theme.muted)
            Spacer()
            if let value {
                Text(value).font(Theme.mono(15)).foregroundStyle(Theme.amber)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

/// `.seg-group` / `.seg-btn` / `.seg-on` — equal-width choices. One row
/// by default; pass `columns` for the wrapping variant.
struct SegGroup: View {
    let options: [(value: String, label: String)]
    @Binding var value: String
    var columns: Int? = nil

    var body: some View {
        let n = max(columns ?? options.count, 1)
        let wrap = columns != nil // .seg-group--wrap: tighter padding, smaller type
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: n), spacing: 8) {
            ForEach(options, id: \.value) { opt in
                let on = value == opt.value
                Button { value = opt.value } label: {
                    Text(opt.label)
                        .font(Theme.body(wrap ? 14 : 15, weight: on ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, wrap ? 11 : 13)
                        .padding(.horizontal, 6)
                        .foregroundStyle(on ? Theme.amber : Theme.textBody)
                        .background(on ? Theme.amberBg : Theme.bgPill)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(on ? Theme.amber : Theme.borderDim))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// `.pill` / `.pill-on` / `.pill-warn` — a full-width toggle row.
struct Pill: View {
    let on: Bool
    var warn = false
    let text: String
    let action: () -> Void

    var body: some View {
        let fg = on ? (warn ? Theme.red : Theme.amber) : Theme.text
        let bg = on ? (warn ? Theme.redBg : Theme.amberBg) : Theme.bgPill
        let stroke = on ? (warn ? Theme.red : Theme.amber) : Theme.borderDim
        Button(action: action) {
            Text(text)
                .font(Theme.body(16))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .foregroundStyle(fg)
                .background(bg)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(stroke))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// `.err-box` — red inline error.
struct ErrorBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.body(13.5))
            .foregroundStyle(Theme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.redBg)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.red))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// `.input` — full-width text field / editor chrome.
private struct CoachInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.body(14.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Theme.bgInput)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.borderDim))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

extension View {
    func coachInput() -> some View { modifier(CoachInputStyle()) }
}
