import Foundation
import PadelStats
import SwiftData

/// A match in the history. Created on the first point and kept in sync with
/// every point/undo, so a match is saved even if the app is quit mid-game.
@Model
final class MatchRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var opponentName: String
    /// Doubles partner. Default keeps older stores migratable.
    var partnerName: String = ""
    /// JSON-encoded `[SetScore]` (keeps tiebreak details).
    var setsData: Data
    /// `Team.rawValue` of the winner, `nil` while running or if abandoned.
    var winnerRaw: String?
    /// `true` once the match is won or replaced by a new match.
    var isCompleted: Bool
    var bestOf: Int
    var goldenPoint: Bool
    /// Match tiebreak instead of a deciding set. Default keeps older stores migratable.
    var superTiebreak: Bool = false

    init(id: UUID = UUID(), startDate: Date = .now, rules: MatchRules) {
        self.id = id
        self.startDate = startDate
        self.endDate = nil
        self.opponentName = ""
        self.partnerName = ""
        self.setsData = Data()
        self.winnerRaw = nil
        self.isCompleted = false
        self.bestOf = rules.bestOf
        self.goldenPoint = rules.deuceRule == .goldenPoint
        self.superTiebreak = rules.superTiebreak
    }

    var sets: [SetScore] {
        get { (try? JSONDecoder().decode([SetScore].self, from: setsData)) ?? [] }
        set { setsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var winner: Team? {
        get { winnerRaw.flatMap(Team.init(rawValue:)) }
        set { winnerRaw = newValue?.rawValue }
    }

    var setsWon: TeamScore {
        sets.reduce(into: TeamScore.zero) { result, set in
            if let winner = set.winner { result[winner] += 1 }
        }
    }

    var status: MatchStatus {
        if let winner { return winner == .me ? .won : .lost }
        return isCompleted ? .abandoned : .live
    }

    var displayTitle: String {
        let name = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Match" : "vs. \(name)"
    }

    /// Copies the score of a running match into the record.
    func apply(_ state: MatchState) {
        sets = state.setScoresIncludingCurrent
        winner = state.winner
        bestOf = state.rules.bestOf
        goldenPoint = state.rules.deuceRule == .goldenPoint
        superTiebreak = state.rules.superTiebreak
        if state.isFinished {
            isCompleted = true
            endDate = endDate ?? .now
        } else {
            isCompleted = false
            endDate = nil
        }
    }

    func markCompleted() {
        isCompleted = true
        endDate = endDate ?? .now
    }
}

enum MatchStatus {
    case live, won, lost, abandoned

    var title: String {
        switch self {
        case .live: "Läuft"
        case .won: "Sieg"
        case .lost: "Niederlage"
        case .abandoned: "Abgebrochen"
        }
    }
}

extension MatchRecord {
    /// Exchange format for the iPhone app.
    var summary: MatchSummary {
        MatchSummary(
            id: id,
            startDate: startDate,
            endDate: endDate,
            opponentName: opponentName,
            partnerName: partnerName,
            sets: sets,
            winner: winner,
            isCompleted: isCompleted,
            bestOf: bestOf,
            goldenPoint: goldenPoint,
            superTiebreak: superTiebreak
        )
    }
}

extension SetScore {
    /// Loser's tiebreak points, as written in tennis results (7:6⁵).
    var tiebreakText: String? {
        guard let tiebreak, !isSuperTiebreak else { return nil }
        return "\(min(tiebreak.me, tiebreak.opponent))"
    }
}
