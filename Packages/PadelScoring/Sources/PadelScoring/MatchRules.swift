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
    /// Play a match tiebreak instead of the deciding set (e.g. at 1:1 sets in a best of 3).
    public var superTiebreak: Bool
    /// Points needed to win the match tiebreak (with a two-point margin).
    public var superTiebreakPoints: Int

    public init(
        bestOf: Int = 3,
        deuceRule: DeuceRule = .advantage,
        gamesPerSet: Int = 6,
        tiebreakPoints: Int = 7,
        superTiebreak: Bool = false,
        superTiebreakPoints: Int = 10
    ) {
        self.bestOf = max(1, bestOf)
        self.deuceRule = deuceRule
        self.gamesPerSet = max(1, gamesPerSet)
        self.tiebreakPoints = max(1, tiebreakPoints)
        self.superTiebreak = superTiebreak
        self.superTiebreakPoints = max(1, superTiebreakPoints)
    }

    /// Sets a team needs to win the match (2 in a best of 3).
    public var setsToWin: Int { bestOf / 2 + 1 }

    public static let standard = MatchRules()

    // Decoding tolerates data saved by older app versions (missing keys → defaults).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bestOf: try container.decode(Int.self, forKey: .bestOf),
            deuceRule: try container.decode(DeuceRule.self, forKey: .deuceRule),
            gamesPerSet: try container.decodeIfPresent(Int.self, forKey: .gamesPerSet) ?? 6,
            tiebreakPoints: try container.decodeIfPresent(Int.self, forKey: .tiebreakPoints) ?? 7,
            superTiebreak: try container.decodeIfPresent(Bool.self, forKey: .superTiebreak) ?? false,
            superTiebreakPoints: try container.decodeIfPresent(Int.self, forKey: .superTiebreakPoints) ?? 10
        )
    }
}
