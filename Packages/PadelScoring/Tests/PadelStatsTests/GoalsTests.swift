import Foundation
import Testing
@testable import PadelStats

@Suite("Weekly goal")
struct WeeklyGoalTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2
        return c
    }
    // Wednesday 12 Nov 2026 12:00 Berlin
    let now = Date(timeIntervalSince1970: 1_799_928_000 - 86_400 * 365 * 0 + 0)

    func match(daysAgo: Double, won: Bool? = true) -> MatchSummary {
        MatchSummary(startDate: now.addingTimeInterval(-daysAgo * 86_400),
                     sets: [SetScore(games: TeamScore(me: 6, opponent: 3))],
                     winner: won.map { $0 ? .me : .opponent }, isCompleted: true)
    }

    @Test func countsThisWeekAndRemaining() {
        let goal = PadelStats.weeklyGoal([match(daysAgo: 0), match(daysAgo: 1), match(daysAgo: 10)], target: 3, now: now, calendar: calendar)
        #expect(goal.playedThisWeek == 2)
        #expect(goal.remaining == 1)
        #expect(goal.isMet == false)
        #expect(abs(goal.progress - 2.0 / 3.0) < 0.001)
    }

    @Test func abandonedMatchesCountAsPlayedLiveDoNot() {
        var live = match(daysAgo: 0, won: nil)
        live.isCompleted = false
        let abandoned = match(daysAgo: 0, won: nil)
        let goal = PadelStats.weeklyGoal([live, abandoned], target: 1, now: now, calendar: calendar)
        #expect(goal.playedThisWeek == 1)
    }

    @Test func streakOfWeeks() {
        // this week: 3 (met), last week: 3 (met), two weeks ago: 1 (not met), three weeks ago: 3
        let matches = [
            match(daysAgo: 0), match(daysAgo: 1), match(daysAgo: 2),
            match(daysAgo: 7), match(daysAgo: 8), match(daysAgo: 9),
            match(daysAgo: 15),
            match(daysAgo: 22), match(daysAgo: 23), match(daysAgo: 24),
        ]
        let goal = PadelStats.weeklyGoal(matches, target: 3, now: now, calendar: calendar)
        #expect(goal.streakWeeks == 2)
    }

    @Test func streakContinuesWhileCurrentWeekIsOpen() {
        let matches = [match(daysAgo: 7), match(daysAgo: 8), match(daysAgo: 9), match(daysAgo: 0)]
        let goal = PadelStats.weeklyGoal(matches, target: 3, now: now, calendar: calendar)
        #expect(goal.isMet == false)
        #expect(goal.streakWeeks == 1, "last week counts, this week is still open")
    }

    @Test func targetNeverBelowOne() {
        let goal = PadelStats.weeklyGoal([], target: 0, now: now, calendar: calendar)
        #expect(goal.target == 1)
        #expect(goal.progress == 0)
    }
}

@Suite("Month review")
struct MonthReviewTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }
    // 10 Nov 2026
    let now = Date(timeIntervalSince1970: 1_794_000_000)

    func match(daysAgo: Double, won: Bool, partner: String = "", opponent: String = "", minutes: Double = 60) -> MatchSummary {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return MatchSummary(startDate: start, endDate: start.addingTimeInterval(minutes * 60),
                            opponentName: opponent, partnerName: partner,
                            sets: [SetScore(games: TeamScore(me: won ? 6 : 3, opponent: won ? 3 : 6))],
                            winner: won ? .me : .opponent, isCompleted: true)
    }

    @Test func lastMonthSummary() throws {
        let matches = [
            match(daysAgo: 20, won: true, partner: "Tom", opponent: "Max"),
            match(daysAgo: 22, won: true, partner: "Tom", opponent: "Max"),
            match(daysAgo: 25, won: false, partner: "Anna", opponent: "Max"),
            match(daysAgo: 28, won: true, partner: "Tom", opponent: "Lena"),
            match(daysAgo: 2, won: true),   // this month – ignored
        ]
        let review = try #require(PadelStats.lastMonthReview(matches, now: now, calendar: calendar))
        #expect(review.matches == 4)
        #expect(review.wins == 3)
        #expect(review.losses == 1)
        #expect(review.favouritePartner == "Tom")
        #expect(review.favouritePartnerMatches == 3)
        #expect(review.toughestRival == "Max")
        #expect(review.bestWinStreak == 2)
        #expect(review.playTime == 4 * 3600)
        #expect(review.winRate == 0.75)
        #expect(calendar.component(.month, from: review.month) == 10)
    }

    @Test func noMatchesNoReview() {
        #expect(PadelStats.lastMonthReview([match(daysAgo: 1, won: true)], now: now, calendar: calendar) == nil)
    }

    @Test func ratingChangeWithinMonth() throws {
        let matches = [match(daysAgo: 20, won: true), match(daysAgo: 22, won: true)]
        let review = try #require(PadelStats.lastMonthReview(matches, now: now, calendar: calendar))
        #expect((review.ratingChange ?? 0) > 0)
    }
}
