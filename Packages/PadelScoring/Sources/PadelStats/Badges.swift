import Foundation

/// An achievement with progress, computed from the match history.
public struct Badge: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    /// SF Symbol name.
    public var symbol: String
    public var current: Int
    public var target: Int

    public var isUnlocked: Bool { current >= target }
    public var progress: Double { min(1, Double(current) / Double(max(target, 1))) }
}

extension PadelStats {
    public static func badges(_ matches: [MatchSummary]) -> [Badge] {
        let decided = decided(matches)
        let overview = overview(matches)
        let wins = decided.filter { $0.winner == .me }

        let tiebreakWins = decided.reduce(0) { count, match in
            count + match.sets.filter { $0.isTiebreakSet && $0.winner == .me }.count
        }
        let comebacks = wins.filter { $0.sets.first?.winner == .opponent }.count
        let bagels = decided.reduce(0) { count, match in
            count + match.sets.filter { !$0.isSuperTiebreak && $0.winner == .me && $0.games.opponent == 0 }.count
        }
        let matchTiebreakWins = wins.filter { $0.sets.last?.isSuperTiebreak == true }.count
        let topRival = rivals(matches).first?.matches ?? 0
        let topPartner = partners(matches).first?.matches ?? 0

        func badge(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ current: Int, _ target: Int) -> Badge {
            Badge(id: id, title: title, detail: detail, symbol: symbol, current: min(current, target), target: target)
        }

        return [
            badge("firstWin", "Erster Sieg", "Gewinne dein erstes Match.", "trophy.fill", wins.count, 1),
            badge("matches10", "Stammspieler", "Spiele 10 Matches.", "figure.tennis", decided.count, 10),
            badge("matches50", "Padel-Profi", "Spiele 50 Matches.", "medal.fill", decided.count, 50),
            badge("streak3", "Lauf", "Gewinne 3 Matches in Folge.", "flame.fill", overview.longestWinStreak, 3),
            badge("streak10", "Unaufhaltsam", "Gewinne 10 Matches in Folge.", "bolt.fill", overview.longestWinStreak, 10),
            badge("tiebreak", "Nervenstark", "Gewinne einen Tiebreak.", "scope", tiebreakWins, 1),
            badge("matchTiebreak", "Eiskalt", "Gewinne einen Match-Tiebreak.", "snowflake", matchTiebreakWins, 1),
            badge("comeback", "Comeback", "Gewinne ein Match nach verlorenem ersten Satz.", "arrow.uturn.up", comebacks, 1),
            badge("bagel", "Zu null", "Gewinne einen Satz 6:0.", "circle.circle", bagels, 1),
            badge("rival", "Erzrivale", "Spiele 5 Matches gegen denselben Gegner.", "person.2.fill", topRival, 5),
            badge("partner", "Eingespieltes Team", "Spiele 10 Matches mit demselben Partner.", "hands.clap.fill", topPartner, 10),
        ]
    }
}
