import PadelStats
import SwiftUI

enum Theme {
    static let me = Color(red: 0.19, green: 0.84, blue: 0.35)
    static let opponent = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let ball = Color(red: 0.86, green: 1.0, blue: 0.31)

    static func scoreFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

extension MatchSummary.Result {
    var title: String {
        switch self {
        case .won: "Sieg"
        case .lost: "Niederlage"
        case .abandoned: "Abgebrochen"
        case .live: "Läuft"
        }
    }

    var color: Color {
        switch self {
        case .won: Theme.me
        case .lost: Theme.opponent
        case .abandoned: .secondary
        case .live: .yellow
        }
    }
}

extension MatchSummary {
    var title: String {
        let name = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Match" : "vs. \(name)"
    }

    var modeText: String {
        let sets = bestOf == 1 ? "1 Satz" : "Best of \(bestOf)"
        return superTiebreak && bestOf > 1 ? "\(sets), Match-Tiebreak" : sets
    }
}

extension Double {
    /// 0.634 → "63 %"
    var percentText: String { formatted(.percent.precision(.fractionLength(0))) }
}

extension TimeInterval {
    /// "1 Std., 25 Min."
    var durationText: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Small "Sieg" / "Niederlage" capsule.
struct ResultBadge: View {
    let result: MatchSummary.Result

    var body: some View {
        Text(result.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(result.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(result.color.opacity(0.15), in: .capsule)
    }
}

/// Glass card used on the overview.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.scoreFont(size: 30))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
