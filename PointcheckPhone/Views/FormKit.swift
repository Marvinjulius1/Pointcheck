import SwiftUI

// Pointcheck's own form language: no system Form/List. Dark sheets with a short
// headline, anthracite groups with a hairline, a tennis ball as the toggle knob,
// pills instead of pickers and balls instead of steppers.

// MARK: - Screen & groups

/// Scrollable sheet body with a headline block and a sticky primary action.
struct FormScreen<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(title: String, subtitle: String? = nil, symbol: String? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                FormHeadline(title: title, subtitle: subtitle, symbol: symbol)
                content
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }
}

/// Big rounded headline with a lime ball in front, like a chapter title.
struct FormHeadline: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: symbol ?? "tennisball.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.lime)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .revealOnAppear()
    }
}

/// Eyebrow + card + optional note underneath.
struct FormGroup<Content: View>: View {
    var title: String?
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Eyebrow(text: title) }
            Card { content }
            if let note {
                FormNote(text: note)
            }
        }
    }
}

/// Footnote with a tiny ball bullet.
struct FormNote: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(tint == .secondary ? Theme.lime : tint).frame(width: 6, height: 6)
                .offset(y: -2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

/// Sticky bottom bar with the primary action.
struct FormActionBar: View {
    let title: String
    var enabled = true
    var isWorking = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Button(action: action) {
                HStack(spacing: 10) {
                    if isWorking {
                        BallLoader(size: 14)
                    }
                    Text(title).font(.headline)
                }
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent, in: .capsule)
            }
            .buttonStyle(.pressScale)
            .disabled(!enabled || isWorking)
            .opacity(enabled ? 1 : 0.4)
            .animation(.snappy, value: enabled)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
    }
}

// MARK: - Rows

/// Row with icon tile, title, optional subtitle and a trailing control.
struct FormRow<Trailing: View>: View {
    var symbol: String?
    var tint: Color = Theme.surfaceRaised
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                IconTile(symbol: symbol, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Switch whose knob is a tennis ball; the track turns lime and the ball rolls over.
struct BallToggle: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.lime.opacity(0.9) : Theme.surfaceRaised)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? Theme.onAccent : Color.white.opacity(0.85))
                    .rotationEffect(.degrees(isOn ? 180 : 0))
                    .padding(3)
            }
            .frame(width: 54, height: 30)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "An" : "Aus")
    }
}

/// Row + ball toggle.
struct ToggleRow: View {
    var symbol: String?
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        FormRow(symbol: symbol, tint: isOn ? Theme.lime : Theme.surfaceRaised, title: title, subtitle: subtitle) {
            BallToggle(isOn: $isOn)
        }
        .animation(.snappy, value: isOn)
    }
}

/// Segmented choice as pills; the selected pill is lime.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == value ? Theme.onAccent : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selection == value {
                                Capsule().fill(Theme.lime).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.surfaceRaised, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Count chooser: a row of balls (filled up to the value) with − / + on the sides.
struct BallCounter: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var maxBalls = 7

    var body: some View {
        HStack(spacing: 14) {
            stepButton("minus") { value = max(range.lowerBound, value - 1) }
                .disabled(value <= range.lowerBound)
            HStack(spacing: 6) {
                ForEach(0..<min(maxBalls, range.upperBound), id: \.self) { index in
                    Image(systemName: "tennisball.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(index < value ? Theme.lime : Theme.surfaceRaised)
                        .scaleEffect(index == value - 1 ? 1.2 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.015), value: value)
                }
                if value > maxBalls {
                    Text("+\(value - maxBalls)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.lime)
                }
            }
            .frame(maxWidth: .infinity)
            stepButton("plus") { value = min(range.upperBound, value + 1) }
                .disabled(value >= range.upperBound)
        }
        .sensoryFeedback(.increase, trigger: value)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Theme.surfaceRaised, in: .circle)
        }
        .buttonStyle(.pressScale)
        .foregroundStyle(Color.primary)
    }
}

/// Text input inside a group: label on top, value below; lime line while focused.
struct InputRow: View {
    let label: String
    var placeholder = ""
    @Binding var text: String
    var symbol: String?
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int> = 1...1
    var lowercase = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let symbol {
                IconTile(symbol: symbol, tint: focused ? Theme.lime : Theme.surfaceRaised)
                    .animation(.snappy, value: focused)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(focused ? Theme.lime : .secondary)
                TextField(placeholder, text: $text, axis: axis)
                    .lineLimit(lineLimit)
                    .focused($focused)
                    .textInputAutocapitalization(lowercase ? .never : .sentences)
                    .autocorrectionDisabled(lowercase)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .animation(.snappy, value: focused)
    }
}

/// Date row with a compact picker, tinted lime.
struct DateRow: View {
    let title: String
    @Binding var date: Date
    var range: PartialRangeFrom<Date>?
    var pastRange: PartialRangeThrough<Date>?
    var components: DatePickerComponents = [.date, .hourAndMinute]

    var body: some View {
        FormRow(symbol: "calendar", tint: Theme.lime, title: title) {
            Group {
                if let range {
                    DatePicker("", selection: $date, in: range, displayedComponents: components)
                } else if let pastRange {
                    DatePicker("", selection: $date, in: pastRange, displayedComponents: components)
                } else {
                    DatePicker("", selection: $date, displayedComponents: components)
                }
            }
            .labelsHidden()
            .tint(Theme.lime)
        }
    }
}

/// Status chip ("Verbunden", "Nicht verfügbar").
struct StatusChip: View {
    let text: String
    var on = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(on ? Theme.lime : Color.secondary).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(on ? Color.primary : .secondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.surfaceRaised, in: .capsule)
    }
}

/// Error line in forms.
struct FormError: View {
    let text: String
    var body: some View {
        FormNote(text: text, tint: Theme.opponent)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Tappable row that only does something (sign out, change password …).
struct ActionRow: View {
    var symbol: String?
    let title: String
    var subtitle: String?
    var destructive = false
    var trailingSymbol: String? = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FormRow(symbol: symbol, tint: destructive ? Theme.opponent : Theme.surfaceRaised, title: title, subtitle: subtitle) {
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(destructive ? Theme.opponent : Color.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.pressScale)
    }
}
