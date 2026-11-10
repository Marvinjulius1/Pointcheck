/// The score of a single set.
public struct SetScore: Codable, Hashable, Sendable {
    public var games: TeamScore
    /// Final tiebreak points, if the set was decided by a tiebreak.
    public var tiebreak: TeamScore?
    /// `false` for a set that was still running when it was recorded.
    public var isComplete: Bool

    public init(games: TeamScore, tiebreak: TeamScore? = nil, isComplete: Bool = true) {
        self.games = games
        self.tiebreak = tiebreak
        self.isComplete = isComplete
    }

    public var winner: Team? {
        isComplete ? games.leader : nil
    }
}

/// What happened as a result of a single point.
public enum PointOutcome: Hashable, Sendable {
    case point(Team)
    case game(Team)
    case set(Team)
    case match(Team)

    public var team: Team {
        switch self {
        case .point(let team), .game(let team), .set(let team), .match(let team):
            return team
        }
    }
}

/// Special situations inside the current game, useful for UI labels.
public enum GameSituation: Hashable, Sendable {
    case regular
    /// 40:40 with advantage scoring.
    case deuce
    /// One team has the advantage.
    case advantage(Team)
    /// 40:40 with golden point scoring – next point wins.
    case goldenPoint
    case tiebreak
}

/// Immutable-by-default snapshot of a match. Pure value type, no UI dependencies.
public struct MatchState: Codable, Hashable, Sendable {
    public let rules: MatchRules
    public private(set) var completedSets: [SetScore] = []
    /// Games in the current set.
    public private(set) var games: TeamScore = .zero
    /// Raw points in the current game (or tiebreak).
    public private(set) var points: TeamScore = .zero
    public private(set) var winner: Team?

    public init(rules: MatchRules = .standard) {
        self.rules = rules
    }

    // MARK: - Derived state

    public var isFinished: Bool { winner != nil }

    public var isTiebreak: Bool {
        games.me == rules.gamesPerSet && games.opponent == rules.gamesPerSet
    }

    public var hasStarted: Bool {
        !completedSets.isEmpty || games.total > 0 || points.total > 0
    }

    public var setsWon: TeamScore {
        completedSets.reduce(into: TeamScore.zero) { result, set in
            if let winner = set.winner { result[winner] += 1 }
        }
    }

    /// All completed sets plus the running set (if any play happened in it).
    public var setScoresIncludingCurrent: [SetScore] {
        guard winner == nil, games.total > 0 || points.total > 0 else { return completedSets }
        return completedSets + [SetScore(games: games, isComplete: false)]
    }

    public var situation: GameSituation {
        if isTiebreak { return .tiebreak }
        guard points.me >= 3, points.opponent >= 3 else { return .regular }
        if let leader = points.leader { return .advantage(leader) }
        return rules.deuceRule == .goldenPoint ? .goldenPoint : .deuce
    }

    /// The label shown for a team in the current game: "0", "15", "30", "40", "AD",
    /// or the plain point count during a tiebreak.
    public func pointLabel(for team: Team) -> String {
        let own = points[team]
        if isTiebreak { return String(own) }
        let other = points[team.other]
        if own >= 3, other >= 3 {
            return own > other ? "AD" : "40"
        }
        return ["0", "15", "30", "40"][min(own, 3)]
    }

    // MARK: - Scoring

    /// Adds a point for `team`. Returns `nil` if the match is already over.
    @discardableResult
    public mutating func scorePoint(for team: Team) -> PointOutcome? {
        guard winner == nil else { return nil }
        points[team] += 1
        return isTiebreak ? resolveTiebreakPoint(for: team) : resolveGamePoint(for: team)
    }

    private mutating func resolveGamePoint(for team: Team) -> PointOutcome {
        let own = points[team]
        let other = points[team.other]
        let wonGame: Bool
        switch rules.deuceRule {
        case .advantage: wonGame = own >= 4 && own - other >= 2
        case .goldenPoint: wonGame = own >= 4 && own > other
        }
        guard wonGame else { return .point(team) }

        points = .zero
        games[team] += 1
        if games[team] >= rules.gamesPerSet, games[team] - games[team.other] >= 2 {
            return finishSet(wonBy: team, tiebreak: nil)
        }
        return .game(team)
    }

    private mutating func resolveTiebreakPoint(for team: Team) -> PointOutcome {
        let own = points[team]
        guard own >= rules.tiebreakPoints, own - points[team.other] >= 2 else { return .point(team) }
        let tiebreak = points
        games[team] += 1
        return finishSet(wonBy: team, tiebreak: tiebreak)
    }

    private mutating func finishSet(wonBy team: Team, tiebreak: TeamScore?) -> PointOutcome {
        completedSets.append(SetScore(games: games, tiebreak: tiebreak))
        games = .zero
        points = .zero
        if setsWon[team] >= rules.setsToWin {
            winner = team
            return .match(team)
        }
        return .set(team)
    }
}
