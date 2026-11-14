import PadelStats
import SwiftUI

/// Design system of the iPhone app: deep black, anthracite surfaces, white/grey text,
/// one accent (padel lime) for wins, progress and primary actions, red only for losses.
enum Theme {
    /// Padel lime – wins, positive change, primary actions.
    static let lime = Color(red: 0.84, green: 1.0, blue: 0.31)
    /// "Me" / win colour (lime).
    static let me = lime
    /// Opponent / loss colour.
    static let opponent = Color(red: 1.0, green: 0.30, blue: 0.27)
    static let ball = lime

    /// Page background.
    static let background = Color(red: 0.0, green: 0.0, blue: 0.0)
    /// Cards and interactive surfaces (anthracite).
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
    /// A step above `surface` (inner tiles, pressed states).
    static let surfaceRaised = Color(red: 0.16, green: 0.16, blue: 0.17)
    /// Subtle outline on surfaces.
    static let hairline = Color.white.opacity(0.08)
    /// Primary action colour and text on it.
    static let accent = lime
    static let onAccent = Color.black

    enum Radius {
        static let card: CGFloat = 20
        static let inner: CGFloat = 14
        static let tile: CGFloat = 12
    }

    enum Spacing {
        static let page: CGFloat = 20
        static let section: CGFloat = 28
        static let card: CGFloat = 16
    }

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
        case .live: Theme.lime
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
