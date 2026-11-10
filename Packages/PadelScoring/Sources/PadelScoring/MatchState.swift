/// The score of a single set.
public struct SetScore: Codable, Hashable, Sendable {
    public var games: TeamScore
    /// Final tiebreak points, if the set was decided by a tiebreak (or is a match tiebreak).
    public var tiebreak: TeamScore?
    /// `false` for a set that was still running when it was recorded.
    public var isComplete: Bool
    /// `true` if this "set" was a match tiebreak (super tiebreak) played instead of a deciding set.
    public var isSuperTiebreak: Bool

    public init(games: TeamScore, tiebreak: TeamScore? = nil, isComplete: Bool = true, isSuperTiebreak: Bool = false) {
        self.games = games
        self.tiebreak = tiebreak
        self.isComplete = isComplete
        self.isSuperTiebreak = isSuperTiebreak
    }

    public var winner: Team? {
        isComplete ? games.leader : nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        games = try container.decode(TeamScore.self, forKey: .games)
        tiebreak = try container.decodeIfPresent(TeamScore.self, forKey: .tiebreak)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
        isSuperTiebreak = try container.decodeIfPresent(Bool.self, forKey: .isSuperTiebreak) ?? false
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
    /// Match tiebreak (to 10) instead of a deciding set.
    case superTiebreak
}

/// What is at stake if a team wins the next point.
public enum BigPoint: Hashable, Sendable {
    case setPoint
    case matchPoint
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
    /// Team serving the first game of the match.
    public private(set) var firstServer: Team = .me

    public init(rules: MatchRules = .standard, firstServer: Team = .me) {
        self.rules = rules
        self.firstServer = firstServer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode(MatchRules.self, forKey: .rules)
        completedSets = try container.decodeIfPresent([SetScore].self, forKey: .completedSets) ?? []
        games = try container.decodeIfPresent(TeamScore.self, forKey: .games) ?? .zero
        points = try container.decodeIfPresent(TeamScore.self, forKey: .points) ?? .zero
        winner = try container.decodeIfPresent(Team.self, forKey: .winner)
        firstServer = try container.decodeIfPresent(Team.self, forKey: .firstServer) ?? .me
    }

    // MARK: - Derived state

    public var isFinished: Bool { winner != nil }

    /// Regular tiebreak at 6:6.
    public var isTiebreak: Bool {
        !isSuperTiebreak && games.me == rules.gamesPerSet && games.opponent == rules.gamesPerSet
    }

    /// Match tiebreak instead of the deciding set (both teams one set away from winning).
    public var isSuperTiebreak: Bool {
        rules.superTiebreak
            && rules.setsToWin > 1
            && winner == nil
            && setsWon.me == rules.setsToWin - 1
            && setsWon.opponent == rules.setsToWin - 1
    }

    /// Points are counted 1, 2, 3 … instead of 15, 30, 40.
    public var isCountingTiebreakPoints: Bool { isTiebreak || isSuperTiebreak }

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
        let running = isSuperTiebreak
            ? SetScore(games: games, tiebreak: points, isComplete: false, isSuperTiebreak: true)
            : SetScore(games: games, isComplete: false)
        return completedSets + [running]
    }

    public var situation: GameSituation {
        if isSuperTiebreak { return .superTiebreak }
        if isTiebreak { return .tiebreak }
        guard points.me >= 3, points.opponent >= 3 else { return .regular }
        if let leader = points.leader { return .advantage(leader) }
        return rules.deuceRule == .goldenPoint ? .goldenPoint : .deuce
    }

    /// The label shown for a team in the current game: "0", "15", "30", "40", "AD",
    /// or the plain point count during a tiebreak.
    public func pointLabel(for team: Team) -> String {
        let own = points[team]
        if isCountingTiebreakPoints { return String(own) }
        let other = points[team.other]
        if own >= 3, other >= 3 {
            return own > other ? "AD" : "40"
        }
        return ["0", "15", "30", "40"][min(own, 3)]
    }

    // MARK: - Serve

    /// Games played so far in the whole match (a tiebreak counts as one game).
    public var gamesPlayed: Int {
        completedSets.reduce(0) { $0 + $1.games.total } + games.total
    }

    /// The team serving the next point.
    ///
    /// Serve alternates every game. In a tiebreak the team due to serve plays the first
    /// point, then serve alternates every two points.
    public var server: Team {
        let gameServer = gamesPlayed.isMultiple(of: 2) ? firstServer : firstServer.other
        guard isCountingTiebreakPoints else { return gameServer }
        let block = (points.total + 1) / 2
        return block.isMultiple(of: 2) ? gameServer : gameServer.other
    }

    /// Chooses who serves first. Only possible before the first point.
    @discardableResult
    public mutating func setFirstServer(_ team: Team) -> Bool {
        guard !hasStarted else { return false }
        firstServer = team
        return true
    }

    // MARK: - Big points & side changes

    /// Set point or match point for `team` on the next point, if any.
    public func bigPoint(for team: Team) -> BigPoint? {
        var next = self
        switch next.scorePoint(for: team) {
        case .match: return .matchPoint
        case .set: return .setPoint
        default: return nil
        }
    }

    /// Whether the teams change ends after the point that produced `outcome`
    /// (call on the state *after* the point).
    ///
    /// Ends change after every odd game of a set; at the end of a set only if it had an odd
    /// number of games; in a (match) tiebreak after every 6 points.
    public func isSideChange(after outcome: PointOutcome) -> Bool {
        switch outcome {
        case .match:
            return false
        case .set:
            guard let last = completedSets.last else { return false }
            return !last.games.total.isMultiple(of: 2) && !last.isSuperTiebreak
        case .game:
            return !games.total.isMultiple(of: 2)
        case .point:
            return isCountingTiebreakPoints && points.total > 0 && points.total.isMultiple(of: 6)
        }
    }

    // MARK: - Scoring

    /// Adds a point for `team`. Returns `nil` if the match is already over.
    @discardableResult
    public mutating func scorePoint(for team: Team) -> PointOutcome? {
        guard winner == nil else { return nil }
        if isSuperTiebreak {
            points[team] += 1
            return resolveSuperTiebreakPoint(for: team)
        }
        let tiebreak = isTiebreak
        points[team] += 1
        return tiebreak ? resolveTiebreakPoint(for: team) : resolveGamePoint(for: team)
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

    private mutating func resolveSuperTiebreakPoint(for team: Team) -> PointOutcome {
        let own = points[team]
        guard own >= rules.superTiebreakPoints, own - points[team.other] >= 2 else { return .point(team) }
        let tiebreak = points
        games[team] += 1
        return finishSet(wonBy: team, tiebreak: tiebreak, isSuperTiebreak: true)
    }

    private mutating func finishSet(wonBy team: Team, tiebreak: TeamScore?, isSuperTiebreak: Bool = false) -> PointOutcome {
        completedSets.append(SetScore(games: games, tiebreak: tiebreak, isSuperTiebreak: isSuperTiebreak))
        games = .zero
        points = .zero
        if setsWon[team] >= rules.setsToWin {
            winner = team
            return .match(team)
        }
        return .set(team)
    }
}
