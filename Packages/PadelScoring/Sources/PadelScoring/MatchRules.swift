/// How a game is decided once both teams reach 40.
public enum DeuceRule: String, Codable, Hashable, Sendable, CaseIterable {
    /// Classic deuce: a team needs two points in a row (advantage, then game).
    case advantage
    /// Golden point: at 40:40 the next point wins the game.
    case goldenPoint
}

/// The configurable rules of a match.
public struct MatchRules: Codable, Hashable, Sendable {
    /// Total number of sets that can be played (1, 3, 5 …). Should be odd.
    public var bestOf: Int
    public var deuceRule: DeuceRule
    /// Games needed to win a set (with a two-game margin).
    public var gamesPerSet: Int
    /// Points needed to win a tiebreak (with a two-point margin).
    public var tiebreakPoints: Int

    public init(
        bestOf: Int = 3,
        deuceRule: DeuceRule = .advantage,
        gamesPerSet: Int = 6,
        tiebreakPoints: Int = 7
    ) {
        self.bestOf = max(1, bestOf)
        self.deuceRule = deuceRule
        self.gamesPerSet = max(1, gamesPerSet)
        self.tiebreakPoints = max(1, tiebreakPoints)
    }

    /// Sets a team needs to win the match (2 in a best of 3).
    public var setsToWin: Int { bestOf / 2 + 1 }

    public static let standard = MatchRules()
}
