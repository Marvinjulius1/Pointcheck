import Foundation
import Testing
@testable import PadelStats

@Suite("Rating engine")
struct RatingEngineTests {
    let date = Date(timeIntervalSince1970: 1_767_225_600)

    func established() -> RatingConfig {
        var config = RatingConfig()
        config.provisionalMatches = 0
        return config
    }

    @Test func expectedScoreIsSymmetric() {
        #expect(RatingEngine.expectedScore(1500, against: 1500) == 0.5)
        let favourite = RatingEngine.expectedScore(1700, against: 1500)
        #expect(abs(favourite + RatingEngine.expectedScore(1500, against: 1700) - 1) < 1e-12)
        #expect(abs(favourite - 0.7597) < 0.0001)
    }

    @Test func equalTeamsWinnerGainsHalfK() {
        var engine = RatingEngine(config: established())
        let changes = engine.apply(DoublesResult(
            date: date, teamA: [.player("a"), .player("b")], teamB: [.player("c"), .player("d")], winner: .me
        ))
        #expect(changes["a"] == 16)
        #expect(changes["c"] == -16)
        #expect(engine.rating(of: "b") == 1516)
        #expect(engine.rating(of: "d") == 1484)
        #expect(engine.ratings["a"]?.wins == 1)
        #expect(engine.ratings["c"]?.losses == 1)
    }

    @Test func zeroSumWithEqualKFactors() {
        var engine = RatingEngine(config: established())
        engine.apply(DoublesResult(date: date, teamA: [.player("a"), .player("b")], teamB: [.player("c"), .player("d")], winner: .me))
        let changes = engine.apply(DoublesResult(
            date: date, teamA: [.player("a"), .player("c")], teamB: [.player("b"), .player("d")], winner: .opponent, gameDifference: -5
        ))
        #expect(abs(changes.values.reduce(0, +)) < 1e-9)
    }

    @Test func upsetMovesMoreThanExpectedWin() {
        var config = established()
        config.initialRating = 1500
        var favouriteWins = RatingEngine(config: config)
        var underdogWins = RatingEngine(config: config)
        // Strong team: two players that won many matches against guests.
        for _ in 0..<10 {
            favouriteWins.apply(DoublesResult(date: date, teamA: [.player("s1"), .player("s2")], teamB: [.guest, .guest], winner: .me))
            underdogWins.apply(DoublesResult(date: date, teamA: [.player("s1"), .player("s2")], teamB: [.guest, .guest], winner: .me))
        }
        let expected = favouriteWins.apply(DoublesResult(
            date: date, teamA: [.player("s1"), .player("s2")], teamB: [.player("w1"), .player("w2")], winner: .me
        ))
        let upset = underdogWins.apply(DoublesResult(
            date: date, teamA: [.player("s1"), .player("s2")], teamB: [.player("w1"), .player("w2")], winner: .opponent
        ))
        #expect(expected["s1"]! > 0)
        #expect(upset["w1"]! > expected["s1"]!)
    }

    @Test func guestsNeverChange() {
        var engine = RatingEngine(config: established())
        let changes = engine.apply(DoublesResult(date: date, teamA: [.player("me"), .guest], teamB: [.guest], winner: .me))
        #expect(changes.keys.sorted() == ["me"])
        #expect(engine.ratings.count == 1)
        #expect(engine.rating(of: "me") == 1516)
    }

    @Test func provisionalPlayersMoveFaster() {
        var engine = RatingEngine()
        let changes = engine.apply(DoublesResult(date: date, teamA: [.player("new")], teamB: [.guest], winner: .me))
        #expect(changes["new"] == 24) // 48 * 0.5
        #expect(engine.isProvisional("new"))
    }

    @Test func marginMultiplierIsCapped() {
        let engine = RatingEngine(config: established())
        #expect(engine.marginMultiplier(0) == 1)
        #expect(abs(engine.marginMultiplier(4) - 1.2) < 1e-12)
        #expect(engine.marginMultiplier(-30) == 1.5)
    }

    @Test func clearWinCountsMore() {
        var close = RatingEngine(config: established())
        var clear = RatingEngine(config: established())
        let tight = close.apply(DoublesResult(date: date, teamA: [.player("a")], teamB: [.player("b")], winner: .me, gameDifference: 1))
        let big = clear.apply(DoublesResult(date: date, teamA: [.player("a")], teamB: [.player("b")], winner: .me, gameDifference: 12))
        #expect(big["a"]! > tight["a"]!)
    }
}

@Suite("Padel level")
struct PadelLevelTests {
    @Test func mapping() {
        #expect(PadelLevel.level(for: 1500) == 3.5)
        #expect(PadelLevel.level(for: 1000) == 1)
        #expect(PadelLevel.level(for: 5000) == 7)
        #expect(PadelLevel.level(for: 0) == 0)
        #expect(PadelLevel.name(for: 3.5) == "Gut")
        #expect(PadelLevel.name(for: 3.4) == "Fortgeschritten")
    }
}

@Suite("Local rating report")
struct LocalRatingTests {
    let base = Date(timeIntervalSince1970: 1_767_225_600)

    func match(_ day: Double, won: Bool?, opponent: String = "", partner: String = "") -> MatchSummary {
        MatchSummary(
            startDate: base.addingTimeInterval(day * 86_400),
            opponentName: opponent,
            partnerName: partner,
            sets: [SetScore(games: TeamScore(me: won == false ? 3 : 6, opponent: won == false ? 6 : 3))],
            winner: won.map { $0 ? .me : .opponent }
        )
    }

    @Test func emptyHistoryStartsAtInitialValue() {
        let report = PadelStats.localRatings([])
        #expect(report.me.rating == 1500)
        #expect(report.me.isProvisional)
        #expect(report.history.isEmpty)
        #expect(report.players.isEmpty)
    }

    @Test func winsRaiseMyRatingAndHistoryIsChronological() {
        let matches = [
            match(2, won: true, opponent: "Max", partner: "Tom"),
            match(1, won: true, opponent: "max", partner: "Tom"),
            match(3, won: nil, opponent: "Max"), // abandoned → ignored
        ]
        let report = PadelStats.localRatings(matches)
        #expect(report.me.matches == 2)
        #expect(report.me.rating > 1500)
        #expect(report.history.count == 3)
        #expect(report.history.map(\.date) == report.history.map(\.date).sorted())
        #expect(report.history.last?.rating == report.me.rating)

        let max = try! #require(report.players.first { $0.name == "Max" })
        #expect(max.matches == 2)
        #expect(max.rating < 1500)
        let tom = try! #require(report.players.first { $0.name == "Tom" })
        #expect(tom.wins == 2)
        #expect(report.players.map(\.rating) == report.players.map(\.rating).sorted(by: >))
    }

    @Test func missingNamesAreGuests() {
        let report = PadelStats.localRatings([match(1, won: false)])
        #expect(report.players.map(\.name) == ["Du"])
        #expect(report.me.rating < 1500)
    }
}
