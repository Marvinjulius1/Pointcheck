import Foundation

// MARK: - Engine (ready for real player accounts in phase 3)

/// Tuning of the doubles Elo rating.
public struct RatingConfig: Hashable, Sendable {
    /// Starting value of every new player.
    public var initialRating: Double = 1500
    /// Change factor for established players.
    public var kFactor: Double = 32
    /// Higher factor while a player has few matches, so new players find their level quickly.
    public var provisionalKFactor: Double = 48
    public var provisionalMatches: Int = 10
    /// Clear wins (game difference) move ratings a bit more – capped at `maxMarginMultiplier`.
    public var marginWeight: Double = 0.05
    public var maxMarginMultiplier: Double = 1.5

    public init() {}

    public static let standard = RatingConfig()
}

/// A participant of a rated match.
public enum RatedPlayer: Hashable, Sendable {
    /// A known player whose rating is tracked.
    case player(String)
    /// Unknown player (e.g. no partner entered): counts with the starting value, never changes.
    case guest
}

public struct DoublesResult: Hashable, Sendable {
    public var date: Date
    public var teamA: [RatedPlayer]
    public var teamB: [RatedPlayer]
    public var winner: Team
    /// Games of team A minus games of team B over the whole match (optional).
    public var gameDifference: Int

    /// `winner == .me` means team A won.
    public init(date: Date, teamA: [RatedPlayer], teamB: [RatedPlayer], winner: Team, gameDifference: Int = 0) {
        self.date = date
        self.teamA = teamA
        self.teamB = teamB
        self.winner = winner
        self.gameDifference = gameDifference
    }
}

public struct PlayerRating: Hashable, Sendable, Identifiable {
    public var id: String
    public var rating: Double
    public var matches: Int
    public var wins: Int

    public var losses: Int { matches - wins }
}

public struct RatingEngine: Sendable {
    public let config: RatingConfig
    public private(set) var ratings: [String: PlayerRating] = [:]

    public init(config: RatingConfig = .standard) {
        self.config = config
    }

    public func rating(of id: String) -> Double {
        ratings[id]?.rating ?? config.initialRating
    }

    public func isProvisional(_ id: String) -> Bool {
        (ratings[id]?.matches ?? 0) < config.provisionalMatches
    }

    /// Probability that a team rated `a` beats a team rated `b`.
    public static func expectedScore(_ a: Double, against b: Double) -> Double {
        1 / (1 + pow(10, (b - a) / 400))
    }

    /// Team strength = average of its players (guests count with the starting value).
    public func teamRating(_ team: [RatedPlayer]) -> Double {
        guard !team.isEmpty else { return config.initialRating }
        let values = team.map { player -> Double in
            if case .player(let id) = player { return rating(of: id) }
            return config.initialRating
        }
        return values.reduce(0, +) / Double(values.count)
    }

    func marginMultiplier(_ gameDifference: Int) -> Double {
        min(1 + config.marginWeight * Double(abs(gameDifference)), config.maxMarginMultiplier)
    }

    /// Applies one match. Returns the rating change per tracked player.
    @discardableResult
    public mutating func apply(_ result: DoublesResult) -> [String: Double] {
        let ratingA = teamRating(result.teamA)
        let ratingB = teamRating(result.teamB)
        let expectedA = Self.expectedScore(ratingA, against: ratingB)
        let scoreA: Double = result.winner == .me ? 1 : 0
        let multiplier = marginMultiplier(result.gameDifference)

        var changes: [String: Double] = [:]
        func change(_ team: [RatedPlayer], score: Double, expected: Double) {
            for case .player(let id) in team {
                let k = isProvisional(id) ? config.provisionalKFactor : config.kFactor
                let delta = k * multiplier * (score - expected)
                changes[id, default: 0] += delta
            }
        }
        change(result.teamA, score: scoreA, expected: expectedA)
        change(result.teamB, score: 1 - scoreA, expected: 1 - expectedA)

        // Write after computing, so team ratings are taken from before the match.
        for (team, won) in [(result.teamA, scoreA == 1), (result.teamB, scoreA == 0)] {
            for case .player(let id) in team {
                var player = ratings[id] ?? PlayerRating(id: id, rating: config.initialRating, matches: 0, wins: 0)
                player.rating += changes[id] ?? 0
                player.matches += 1
                if won { player.wins += 1 }
                ratings[id] = player
            }
        }
        return changes
    }
}

// MARK: - Padel level

public enum PadelLevel {
    /// Maps a rating to the common 1.0–7.0 padel level scale (1500 ≈ 3.5).
    public static func level(for rating: Double) -> Double {
        min(7, max(0, 1 + (rating - 1000) / 200))
    }

    public static func name(for level: Double) -> String {
        switch level {
        case ..<1.5: "Einsteiger"
        case ..<2.5: "Anfänger"
        case ..<3.5: "Fortgeschritten"
        case ..<4.5: "Gut"
        case ..<5.5: "Sehr gut"
        case ..<6.5: "Turnierspieler"
        default: "Profi"
        }
    }
}

// MARK: - Local preview from the own history

/// Rating of the watch wearer and the people in their matches, computed only from
/// the own history. In phase 3 every player has an account and the values become exact.
public struct LocalRatingReport: Hashable, Sendable {
    public struct Entry: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var rating: Double
        public var matches: Int
        public var wins: Int
        public var isMe: Bool
        public var isProvisional: Bool

        public var level: Double { PadelLevel.level(for: rating) }
    }

    public struct Point: Hashable, Sendable, Identifiable {
        public var date: Date
        public var rating: Double
        public var id: Date { date }
    }

    public var me: Entry
    /// My rating after each decided match, oldest first (starts with the initial value).
    public var history: [Point]
    /// Everyone incl. me, strongest first.
    public var players: [Entry]
}

extension PadelStats {
    static let meID = "me"

    public static func localRatings(_ matches: [MatchSummary], config: RatingConfig = .standard) -> LocalRatingReport {
        var engine = RatingEngine(config: config)
        var names: [String: String] = [:]
        let chronological = matches.filter(\.isDecided).sorted { $0.startDate < $1.startDate }

        func person(_ raw: String, prefix: String) -> RatedPlayer {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .guest }
            let id = "\(prefix):\(name.lowercased())"
            names[id] = name // newest spelling wins
            return .player(id)
        }

        var history: [LocalRatingReport.Point] = []
        if let first = chronological.first {
            history.append(.init(date: first.startDate.addingTimeInterval(-1), rating: config.initialRating))
        }
        for match in chronological {
            let games = match.sets.reduce(0) { $0 + $1.games.me - $1.games.opponent }
            engine.apply(DoublesResult(
                date: match.startDate,
                teamA: [.player(meID), person(match.partnerName, prefix: "partner")],
                // The opponent name usually stands for the whole opposing team.
                teamB: [person(match.opponentName, prefix: "opponent")],
                winner: match.winner ?? .opponent,
                gameDifference: games
            ))
            history.append(.init(date: match.startDate, rating: engine.rating(of: meID)))
        }

        func entry(_ rating: PlayerRating) -> LocalRatingReport.Entry {
            .init(
                id: rating.id,
                name: rating.id == meID ? "Du" : names[rating.id] ?? rating.id,
                rating: rating.rating,
                matches: rating.matches,
                wins: rating.wins,
                isMe: rating.id == meID,
                isProvisional: rating.matches < config.provisionalMatches
            )
        }
        let me = engine.ratings[meID].map(entry) ?? .init(
            id: meID, name: "Du", rating: config.initialRating, matches: 0, wins: 0, isMe: true, isProvisional: true
        )
        let players = engine.ratings.values.map(entry).sorted { $0.rating > $1.rating }
        return LocalRatingReport(me: me, history: history, players: players)
    }
}

// MARK: - Chart series

public struct RatingPoint: Hashable, Sendable, Identifiable {
    public var date: Date
    public var rating: Double
    public var id: Date { date }

    public init(date: Date, rating: Double) {
        self.date = date
        self.rating = rating
    }
}

public enum RatingSeries {
    /// Points to draw for a time window, like a stock chart:
    /// starts with the value valid at `start` (if there is history before it), contains every
    /// change inside the window and ends with the current value at `now`. Always ≥ 2 points.
    public static func window(_ points: [RatingPoint], current: Double, since start: Date?, now: Date) -> [RatingPoint] {
        let sorted = points.sorted { $0.date < $1.date }.filter { $0.date <= now }
        var result: [RatingPoint] = []
        if let start {
            if let before = sorted.last(where: { $0.date < start }) {
                result.append(RatingPoint(date: start, rating: before.rating))
            }
            result += sorted.filter { $0.date >= start }
        } else {
            result = sorted
        }
        if result.last?.date != now {
            result.append(RatingPoint(date: now, rating: current))
        }
        if result.count == 1 {
            let from = start ?? now.addingTimeInterval(-86_400)
            result.insert(RatingPoint(date: from, rating: current), at: 0)
        }
        return result
    }

    /// Change from the first to the last point of a window.
    public static func change(_ window: [RatingPoint]) -> (delta: Double, base: Double) {
        guard let first = window.first, let last = window.last else { return (0, 0) }
        return (last.rating - first.rating, first.rating)
    }
}
