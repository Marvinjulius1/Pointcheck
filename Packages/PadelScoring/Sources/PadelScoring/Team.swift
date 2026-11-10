/// One side of the court.
public enum Team: String, Codable, Hashable, Sendable, CaseIterable {
    /// The watch wearer and their partner.
    case me
    /// The opposing team.
    case opponent

    public var other: Team {
        self == .me ? .opponent : .me
    }
}

/// A pair of counters, one per team (points, games or sets).
public struct TeamScore: Codable, Hashable, Sendable {
    public var me: Int
    public var opponent: Int

    public init(me: Int = 0, opponent: Int = 0) {
        self.me = me
        self.opponent = opponent
    }

    public static let zero = TeamScore()

    public subscript(team: Team) -> Int {
        get { team == .me ? me : opponent }
        set {
            if team == .me { me = newValue } else { opponent = newValue }
        }
    }

    public var total: Int { me + opponent }

    /// The team with the higher value, or `nil` on a tie.
    public var leader: Team? {
        if me > opponent { return .me }
        if opponent > me { return .opponent }
        return nil
    }
}
