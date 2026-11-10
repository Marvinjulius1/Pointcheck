import Foundation

/// Key figures over all decided matches.
public struct StatsOverview: Hashable, Sendable {
    public var matchesPlayed: Int
    public var wins: Int
    public var losses: Int
    public var setsWon: Int
    public var setsLost: Int
    public var tiebreaksWon: Int
    public var tiebreaksLost: Int
    /// Current run of wins (positive) or losses (negative), newest match first.
    public var currentStreak: Int
    public var longestWinStreak: Int
    public var totalPlayTime: TimeInterval

    /// 0…1, `nil` without decided matches.
    public var winRate: Double? {
        matchesPlayed > 0 ? Double(wins) / Double(matchesPlayed) : nil
    }

    public var tiebreakWinRate: Double? {
        let total = tiebreaksWon + tiebreaksLost
        return total > 0 ? Double(tiebreaksWon) / Double(total) : nil
    }
}

/// Record with/against one person (partner or opponent).
public struct PersonRecord: Hashable, Sendable, Identifiable {
    public var name: String
    public var matches: Int
    public var wins: Int
    public var lastPlayed: Date

    public var id: String { name.lowercased() }
    public var losses: Int { matches - wins }
    public var winRate: Double { matches > 0 ? Double(wins) / Double(matches) : 0 }
}

public struct WeekCount: Hashable, Sendable, Identifiable {
    /// Start of the week.
    public var week: Date
    public var wins: Int
    public var losses: Int

    public var id: Date { week }
    public var total: Int { wins + losses }
}

public enum PadelStats {
    /// Decided matches, newest first.
    static func decided(_ matches: [MatchSummary]) -> [MatchSummary] {
        matches.filter(\.isDecided).sorted { $0.startDate > $1.startDate }
    }

    public static func overview(_ matches: [MatchSummary]) -> StatsOverview {
        let decided = decided(matches)
        var overview = StatsOverview(
            matchesPlayed: decided.count, wins: 0, losses: 0, setsWon: 0, setsLost: 0,
            tiebreaksWon: 0, tiebreaksLost: 0, currentStreak: 0, longestWinStreak: 0, totalPlayTime: 0
        )
        for match in decided {
            if match.winner == .me { overview.wins += 1 } else { overview.losses += 1 }
            overview.setsWon += match.setsWon.me
            overview.setsLost += match.setsWon.opponent
            for set in match.sets where set.isTiebreakSet {
                if set.winner == .me { overview.tiebreaksWon += 1 } else { overview.tiebreaksLost += 1 }
            }
            overview.totalPlayTime += match.duration ?? 0
        }

        // Current streak: newest matches with the same result.
        if let latest = decided.first?.winner {
            let run = decided.prefix { $0.winner == latest }.count
            overview.currentStreak = latest == .me ? run : -run
        }

        // Longest win streak in chronological order.
        var run = 0
        for match in decided.reversed() {
            run = match.winner == .me ? run + 1 : 0
            overview.longestWinStreak = max(overview.longestWinStreak, run)
        }
        return overview
    }

    /// Records grouped by partner name (case-insensitive), most matches first.
    public static func partners(_ matches: [MatchSummary]) -> [PersonRecord] {
        people(matches, name: \.partnerName)
    }

    /// Head-to-head records grouped by opponent name, most matches first.
    public static func rivals(_ matches: [MatchSummary]) -> [PersonRecord] {
        people(matches, name: \.opponentName)
    }

    private static func people(_ matches: [MatchSummary], name: KeyPath<MatchSummary, String>) -> [PersonRecord] {
        var records: [String: PersonRecord] = [:]
        // Newest first, so the stored spelling is the most recent one.
        for match in decided(matches) {
            let display = match[keyPath: name].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = display.lowercased()
            var record = records[key] ?? PersonRecord(name: display, matches: 0, wins: 0, lastPlayed: match.startDate)
            record.matches += 1
            if match.winner == .me { record.wins += 1 }
            record.lastPlayed = max(record.lastPlayed, match.startDate)
            records[key] = record
        }
        return records.values.sorted {
            if $0.matches != $1.matches { return $0.matches > $1.matches }
            if $0.winRate != $1.winRate { return $0.winRate > $1.winRate }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Wins and losses per week for the last `weeks` weeks (oldest first, empty weeks included).
    public static func matchesPerWeek(
        _ matches: [MatchSummary],
        weeks: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekCount] {
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var counts: [WeekCount] = (0..<weeks).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset - weeks + 1, to: thisWeek)
                .map { WeekCount(week: $0, wins: 0, losses: 0) }
        }
        for match in decided(matches) {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: match.startDate)?.start,
                  let index = counts.firstIndex(where: { $0.week == start }) else { continue }
            if match.winner == .me { counts[index].wins += 1 } else { counts[index].losses += 1 }
        }
        return counts
    }
}
