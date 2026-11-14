import Foundation

/// Weekly match goal ("3 Matches pro Woche") with a streak of weeks that met it.
public struct WeeklyGoal: Hashable, Sendable {
    public var target: Int
    /// Matches played in the current week (decided or not – playing counts).
    public var playedThisWeek: Int
    /// Consecutive weeks (before the current one) that met the goal, plus the current
    /// week once it is met.
    public var streakWeeks: Int

    public var progress: Double { target > 0 ? min(1, Double(playedThisWeek) / Double(target)) : 0 }
    public var isMet: Bool { playedThisWeek >= target }
    public var remaining: Int { max(0, target - playedThisWeek) }
}

/// One month in review.
public struct MonthReview: Hashable, Sendable, Identifiable {
    public var month: Date
    public var matches: Int
    public var wins: Int
    public var losses: Int
    public var bestWinStreak: Int
    public var favouritePartner: String?
    public var favouritePartnerMatches: Int
    public var toughestRival: String?
    public var playTime: TimeInterval
    public var ratingChange: Double?

    public var id: Date { month }
    public var winRate: Double? { matches > 0 ? Double(wins) / Double(matches) : nil }
}

extension PadelStats {
    /// Progress of the weekly goal, counting every match that was played (also abandoned ones).
    public static func weeklyGoal(
        _ matches: [MatchSummary],
        target: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyGoal {
        let target = max(1, target)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return WeeklyGoal(target: target, playedThisWeek: 0, streakWeeks: 0)
        }
        var perWeek: [Date: Int] = [:]
        for match in matches where match.result != .live {
            if let week = calendar.dateInterval(of: .weekOfYear, for: match.startDate)?.start {
                perWeek[week, default: 0] += 1
            }
        }
        let current = perWeek[thisWeek] ?? 0

        var streak = 0
        var week = thisWeek
        if current >= target { streak += 1 }
        while let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week),
              (perWeek[previous] ?? 0) >= target {
            streak += 1
            week = previous
        }
        return WeeklyGoal(target: target, playedThisWeek: current, streakWeeks: streak)
    }

    /// Review of the month that contains `date` (decided matches only).
    public static func monthReview(
        _ matches: [MatchSummary],
        for date: Date,
        calendar: Calendar = .current
    ) -> MonthReview? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        let inMonth = matches.filter { $0.isDecided && interval.contains($0.startDate) }
        guard !inMonth.isEmpty else { return nil }

        let overview = overview(inMonth)
        let partners = partners(inMonth)
        let rivals = rivals(inMonth)
        let toughest = rivals.max { lhs, rhs in
            if lhs.losses != rhs.losses { return lhs.losses < rhs.losses }
            return lhs.matches < rhs.matches
        }

        // Rating change: local preview from the whole history, first vs. last point in the month.
        let report = localRatings(matches)
        let points = report.history.filter { interval.contains($0.date) }
        let before = report.history.last { $0.date < interval.start }?.rating
        let change: Double? = {
            guard let last = points.last?.rating else { return nil }
            return last - (before ?? points.first?.rating ?? last)
        }()

        return MonthReview(
            month: interval.start,
            matches: overview.matchesPlayed,
            wins: overview.wins,
            losses: overview.losses,
            bestWinStreak: overview.longestWinStreak,
            favouritePartner: partners.first?.name,
            favouritePartnerMatches: partners.first?.matches ?? 0,
            toughestRival: (toughest?.losses ?? 0) > 0 ? toughest?.name : nil,
            playTime: overview.totalPlayTime,
            ratingChange: change
        )
    }

    /// Review of the previous month, if anything was played.
    public static func lastMonthReview(_ matches: [MatchSummary], now: Date = .now, calendar: Calendar = .current) -> MonthReview? {
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        return monthReview(matches, for: lastMonth, calendar: calendar)
    }
}
