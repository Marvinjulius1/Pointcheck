import PadelScoring
import SwiftUI

enum Theme {
    static let me = Color(red: 0.19, green: 0.84, blue: 0.35)        // system-green family
    static let opponent = Color(red: 1.0, green: 0.27, blue: 0.23)   // system-red family
    static let fieldCornerRadius: CGFloat = 30

    static func color(for team: Team) -> Color {
        team == .me ? me : opponent
    }

    static func title(for team: Team) -> String {
        team == .me ? "Wir" : "Gegner"
    }

    /// SF Pro Rounded, bold, with monospaced digits – the Apple scoreboard look.
    static func scoreFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}

extension MatchStatus {
    var color: Color {
        switch self {
        case .won: Theme.me
        case .lost: Theme.opponent
        case .live: .yellow
        case .abandoned: .secondary
        }
    }
}
