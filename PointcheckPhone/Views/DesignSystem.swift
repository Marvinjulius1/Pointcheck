import SwiftUI

// Calm, finance-app inspired building blocks: big numbers, quiet grouped cards,
// colour only where it carries meaning (up = green, down = red).

/// Grouped card like in Apple's Settings / Trade Republic lists.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Bold section title with an optional trailing link.
struct SectionTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            trailing
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Row with a tinted icon tile, title, optional subtitle and a trailing value.
struct MetricRow: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var subtitle: String?
    let value: String
    var valueTint: Color = .primary

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueTint)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Rounded square with an SF Symbol, like the icons in Apple's Settings.
struct IconTile: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Hairline divider inset to the row text (after the icon tile).
struct RowDivider: View {
    var inset: CGFloat = 62

    var body: some View {
        Divider().padding(.leading, inset)
    }
}

/// "▲ 34 (2,3 %)" in green or red.
struct ChangeLabel: View {
    let change: Double
    let base: Double
    var suffix: String?

    private var isUp: Bool { change >= 0 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.footnote.weight(.bold))
            Text(changeText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            if let suffix {
                Text(suffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isUp ? Theme.me : Theme.opponent)
    }

    private var changeText: String {
        let points = Int(change.rounded())
        let percent = base > 0 ? abs(change) / base : 0
        let sign = points >= 0 ? "+" : "−"
        return "\(sign)\(abs(points)) (\(percent.formatted(.percent.precision(.fractionLength(1)))))"
    }
}

/// Row of capsule buttons to pick a time range ("1W 1M 3M 1J Max").
struct RangePicker<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values) { value in
                let selected = value == selection
                Button {
                    withAnimation(.snappy) { selection = value }
                } label: {
                    Text(title(value))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color(.systemBackground) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule().fill(tint)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
