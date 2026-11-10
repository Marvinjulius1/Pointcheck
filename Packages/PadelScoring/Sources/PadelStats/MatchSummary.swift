import Foundation
@_exported import PadelScoring

/// A finished (or running) match as stored in the history.
///
/// This is the exchange format between watch and iPhone (JSON via WatchConnectivity,
/// later iCloud) and the input for all statistics.
public struct MatchSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date?
    public var opponentName: String
    public var partnerName: String
    public var sets: [SetScore]
    public var winner: Team?
    /// `true` once the match is won or replaced by a new match.
    public var isCompleted: Bool
    public var bestOf: Int
    public var goldenPoint: Bool
    public var superTiebreak: Bool

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        opponentName: String = "",
        partnerName: String = "",
        sets: [SetScore] = [],
        winner: Team? = nil,
        isCompleted: Bool = true,
        bestOf: Int = 3,
        goldenPoint: Bool = false,
        superTiebreak: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.opponentName = opponentName
        self.partnerName = partnerName
        self.sets = sets
        self.winner = winner
        self.isCompleted = isCompleted
        self.bestOf = bestOf
        self.goldenPoint = goldenPoint
        self.superTiebreak = superTiebreak
    }

    public enum Result: String, Codable, Sendable {
        case won, lost, abandoned, live
    }

    public var result: Result {
        if let winner { return winner == .me ? .won : .lost }
        return isCompleted ? .abandoned : .live
    }

    /// Won or lost – abandoned and running matches don't count in statistics.
    public var isDecided: Bool { winner != nil }

    public var setsWon: TeamScore {
        sets.reduce(into: TeamScore.zero) { result, set in
            if let winner = set.winner { result[winner] += 1 }
        }
    }

    public var duration: TimeInterval? {
        endDate.map { $0.timeIntervalSince(startDate) }
    }

    /// "6:4  3:6  [10:8]" from my perspective.
    public var resultText: String {
        guard !sets.isEmpty else { return "0:0" }
        return sets.map(\.resultText).joined(separator: "  ")
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        opponentName = try c.decodeIfPresent(String.self, forKey: .opponentName) ?? ""
        partnerName = try c.decodeIfPresent(String.self, forKey: .partnerName) ?? ""
        sets = try c.decodeIfPresent([SetScore].self, forKey: .sets) ?? []
        winner = try c.decodeIfPresent(Team.self, forKey: .winner)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? true
        bestOf = try c.decodeIfPresent(Int.self, forKey: .bestOf) ?? 3
        goldenPoint = try c.decodeIfPresent(Bool.self, forKey: .goldenPoint) ?? false
        superTiebreak = try c.decodeIfPresent(Bool.self, forKey: .superTiebreak) ?? false
    }
}

extension SetScore {
    /// "6:4" (from my perspective); a match tiebreak is written as "[10:8]".
    public var resultText: String {
        if isSuperTiebreak, let tiebreak {
            return "[\(tiebreak.me):\(tiebreak.opponent)]"
        }
        return "\(games.me):\(games.opponent)"
    }

    /// A regular 7:6 tiebreak set (not a match tiebreak).
    public var isTiebreakSet: Bool { tiebreak != nil && !isSuperTiebreak && isComplete }
}

extension MatchSummary {
    /// JSON coding used for the watch ↔ iPhone transfer.
    public static func encodeList(_ matches: [MatchSummary]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(matches)
    }

    public static func decodeList(_ data: Data) throws -> [MatchSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MatchSummary].self, from: data)
    }
}

extension TeamScore {
    /// The same score seen by the other team.
    public var flipped: TeamScore { TeamScore(me: opponent, opponent: me) }
}

extension SetScore {
    /// The same set seen by the other team.
    public var flipped: SetScore {
        SetScore(games: games.flipped, tiebreak: tiebreak?.flipped, isComplete: isComplete, isSuperTiebreak: isSuperTiebreak)
    }
}

extension MatchSummary {
    /// The same match seen by the other team (sets, winner, names swapped).
    public var flipped: MatchSummary {
        var copy = self
        copy.sets = sets.map(\.flipped)
        copy.winner = winner?.other
        return copy
    }
}
