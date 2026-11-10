import Foundation
import Testing
@testable import PadelStats

// MARK: - Fixtures

private let day: TimeInterval = 86_400
private let base = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

private func set(_ me: Int, _ opponent: Int, tiebreak: (Int, Int)? = nil, superTiebreak: Bool = false) -> SetScore {
    SetScore(
        games: TeamScore(me: me, opponent: opponent),
        tiebreak: tiebreak.map { TeamScore(me: $0.0, opponent: $0.1) },
        isSuperTiebreak: superTiebreak
    )
}

private func match(
    daysAgo: Double = 0,
    won: Bool?,
    sets: [SetScore] = [],
    opponent: String = "",
    partner: String = "",
    minutes: Double = 60
) -> MatchSummary {
    let start = base.addingTimeInterval(-daysAgo * day)
    return MatchSummary(
        startDate: start,
        endDate: start.addingTimeInterval(minutes * 60),
        opponentName: opponent,
        partnerName: partner,
        sets: sets.isEmpty ? (won == true ? [set(6, 3), set(6, 4)] : won == false ? [set(3, 6), set(4, 6)] : []) : sets,
        winner: won.map { $0 ? Team.me : .opponent },
        isCompleted: true
    )
}

// MARK: - Overview

@Suite("Overview")
struct OverviewTests {
    @Test func emptyHistory() {
        let overview = PadelStats.overview([])
        #expect(overview.matchesPlayed == 0)
        #expect(overview.winRate == nil)
        #expect(overview.currentStreak == 0)
    }

    @Test func countsOnlyDecidedMatches() {
        let matches = [
            match(daysAgo: 3, won: true),
            match(daysAgo: 2, won: false),
            match(daysAgo: 1, won: nil), // abandoned
        ]
        let overview = PadelStats.overview(matches)
        #expect(overview.matchesPlayed == 2)
        #expect(overview.wins == 1)
        #expect(overview.losses == 1)
        #expect(overview.winRate == 0.5)
        #expect(overview.setsWon == 2)
        #expect(overview.setsLost == 2)
        #expect(overview.totalPlayTime == 2 * 3600)
    }

    @Test func streaks() {
        // Chronological: W W W L W W
        let results = [true, true, true, false, true, true]
        let matches = results.enumerated().map { index, won in
            match(daysAgo: Double(results.count - index), won: won)
        }
        let overview = PadelStats.overview(matches)
        #expect(overview.currentStreak == 2)
        #expect(overview.longestWinStreak == 3)
    }

    @Test func losingStreakIsNegative() {
        let matches = [match(daysAgo: 3, won: true), match(daysAgo: 2, won: false), match(daysAgo: 1, won: false)]
        #expect(PadelStats.overview(matches).currentStreak == -2)
    }

    @Test func tiebreakRecordIgnoresMatchTiebreaks() {
        let matches = [
            match(won: true, sets: [set(7, 6, tiebreak: (7, 4)), set(6, 7, tiebreak: (5, 7)), set(1, 0, tiebreak: (10, 8), superTiebreak: true)]),
        ]
        let overview = PadelStats.overview(matches)
        #expect(overview.tiebreaksWon == 1)
        #expect(overview.tiebreaksLost == 1)
        #expect(overview.tiebreakWinRate == 0.5)
    }
}

// MARK: - People

@Suite("Partners and rivals")
struct PeopleTests {
    @Test func groupsCaseInsensitiveAndKeepsNewestSpelling() {
        let matches = [
            match(daysAgo: 5, won: true, opponent: "max"),
            match(daysAgo: 4, won: false, opponent: "Max "),
            match(daysAgo: 3, won: true, opponent: "Max"),
            match(daysAgo: 2, won: true, opponent: "Lena"),
            match(daysAgo: 1, won: true, opponent: ""),
        ]
        let rivals = PadelStats.rivals(matches)
        #expect(rivals.count == 2)
        #expect(rivals[0].name == "Max")
        #expect(rivals[0].matches == 3)
        #expect(rivals[0].wins == 2)
        #expect(rivals[0].losses == 1)
        #expect(rivals[1].name == "Lena")
    }

    @Test func partnersSortedByMatchesThenWinRate() {
        let matches = [
            match(daysAgo: 4, won: true, partner: "Tom"),
            match(daysAgo: 3, won: false, partner: "Tom"),
            match(daysAgo: 2, won: true, partner: "Anna"),
            match(daysAgo: 1, won: true, partner: "Anna"),
            match(daysAgo: 0.5, won: true, partner: "Ben"),
        ]
        let partners = PadelStats.partners(matches)
        #expect(partners.map(\.name) == ["Anna", "Tom", "Ben"])
        #expect(partners[0].winRate == 1)
        #expect(partners[1].winRate == 0.5)
    }

    @Test func abandonedMatchesDoNotCount() {
        let matches = [match(won: nil, opponent: "Max")]
        #expect(PadelStats.rivals(matches).isEmpty)
    }
}

// MARK: - Weeks

@Suite("Matches per week")
struct WeekTests {
    @Test func bucketsByWeekIncludingEmptyWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        let matches = [
            match(daysAgo: 0, won: true),
            match(daysAgo: 0.1, won: false),
            match(daysAgo: 15, won: true),
        ]
        let weeks = PadelStats.matchesPerWeek(matches, weeks: 4, now: base, calendar: calendar)
        #expect(weeks.count == 4)
        #expect(weeks.last?.wins == 1)
        #expect(weeks.last?.losses == 1)
        #expect(weeks.map(\.total).reduce(0, +) == 3)
        #expect(weeks.map(\.week) == weeks.map(\.week).sorted())
    }
}

// MARK: - Badges

@Suite("Badges")
struct BadgeTests {
    private func badge(_ id: String, in matches: [MatchSummary]) -> Badge {
        PadelStats.badges(matches).first { $0.id == id }!
    }

    @Test func nothingUnlockedWithoutMatches() {
        #expect(PadelStats.badges([]).allSatisfy { !$0.isUnlocked })
    }

    @Test func firstWinAndProgress() {
        let matches = [match(daysAgo: 2, won: false), match(daysAgo: 1, won: true)]
        #expect(badge("firstWin", in: matches).isUnlocked)
        let tenMatches = badge("matches10", in: matches)
        #expect(tenMatches.current == 2)
        #expect(tenMatches.progress == 0.2)
        #expect(!tenMatches.isUnlocked)
    }

    @Test func comebackBagelAndMatchTiebreak() {
        let matches = [
            match(won: true, sets: [set(2, 6), set(6, 0), set(1, 0, tiebreak: (10, 7), superTiebreak: true)]),
        ]
        #expect(badge("comeback", in: matches).isUnlocked)
        #expect(badge("bagel", in: matches).isUnlocked)
        #expect(badge("matchTiebreak", in: matches).isUnlocked)
        #expect(!badge("tiebreak", in: matches).isUnlocked)
    }

    @Test func progressIsCappedAtTarget() {
        let matches = (0..<4).map { match(daysAgo: Double(4 - $0), won: true) }
        let streak = badge("streak3", in: matches)
        #expect(streak.current == 3)
        #expect(streak.isUnlocked)
    }
}

// MARK: - Transfer format

@Suite("Transfer")
struct TransferTests {
    @Test func listRoundTrip() throws {
        let matches = [
            match(won: true, opponent: "Max", partner: "Tom"),
            match(won: nil, sets: [set(1, 0, tiebreak: (4, 2), superTiebreak: true)]),
        ]
        let data = try MatchSummary.encodeList(matches)
        let decoded = try MatchSummary.decodeList(data)
        #expect(decoded == matches)
    }

    @Test func resultText() {
        let summary = match(won: true, sets: [set(6, 4), set(3, 6), set(1, 0, tiebreak: (10, 8), superTiebreak: true)])
        #expect(summary.resultText == "6:4  3:6  [10:8]")
        #expect(summary.result == .won)
    }

    @Test func decodesWithoutOptionalFields() throws {
        let json = #"[{"id":"7C1D8C3E-0E4A-4C55-9C7A-2F1A1B2C3D4E","startDate":"2026-01-01T10:00:00Z"}]"#
        let decoded = try MatchSummary.decodeList(Data(json.utf8))
        #expect(decoded.first?.partnerName == "")
        #expect(decoded.first?.isCompleted == true)
    }
}
