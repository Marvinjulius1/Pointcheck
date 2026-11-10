import Foundation
import Testing
@testable import PadelScoring

// MARK: - Helpers

extension MatchState {
    mutating func score(_ team: Team, times: Int) {
        for _ in 0..<times { scorePoint(for: team) }
    }

    /// Wins a game from 0:0 without conceding a point.
    mutating func winGame(_ team: Team) {
        score(team, times: 4)
    }

    mutating func winGames(_ team: Team, _ count: Int) {
        for _ in 0..<count { winGame(team) }
    }

    /// Wins a set 6:0.
    mutating func winSet(_ team: Team) {
        winGames(team, rules.gamesPerSet)
    }

    /// Plays a set up to 6:6.
    mutating func reachTiebreak() {
        for _ in 0..<rules.gamesPerSet {
            winGame(.me)
            winGame(.opponent)
        }
    }

    var labels: String { "\(pointLabel(for: .me)):\(pointLabel(for: .opponent))" }
}

// MARK: - Points

@Suite("Points within a game")
struct PointTests {
    @Test func startsAtLove() {
        let state = MatchState()
        #expect(state.labels == "0:0")
        #expect(state.hasStarted == false)
        #expect(state.situation == .regular)
    }

    @Test func pointsProgressLikeTennis() {
        var state = MatchState()
        #expect(state.scorePoint(for: .me) == .point(.me))
        #expect(state.labels == "15:0")
        state.scorePoint(for: .me)
        #expect(state.labels == "30:0")
        state.scorePoint(for: .me)
        #expect(state.labels == "40:0")
        state.scorePoint(for: .opponent)
        #expect(state.labels == "40:15")
        #expect(state.hasStarted)
    }

    @Test func fourthPointWinsGameAndResetsPoints() {
        var state = MatchState()
        state.score(.me, times: 3)
        #expect(state.scorePoint(for: .me) == .game(.me))
        #expect(state.games == TeamScore(me: 1, opponent: 0))
        #expect(state.points == .zero)
        #expect(state.labels == "0:0")
    }

    @Test func opponentCanWinGames() {
        var state = MatchState()
        state.score(.opponent, times: 3)
        #expect(state.scorePoint(for: .opponent) == .game(.opponent))
        #expect(state.games == TeamScore(me: 0, opponent: 1))
    }
}

// MARK: - Deuce / Advantage

@Suite("Deuce with advantage")
struct AdvantageTests {
    @Test func fortyAllIsDeuce() {
        var state = MatchState()
        state.score(.me, times: 3)
        state.score(.opponent, times: 3)
        #expect(state.labels == "40:40")
        #expect(state.situation == .deuce)
    }

    @Test func advantageThenBackToDeuce() {
        var state = MatchState()
        state.score(.me, times: 3)
        state.score(.opponent, times: 3)

        #expect(state.scorePoint(for: .me) == .point(.me))
        #expect(state.labels == "AD:40")
        #expect(state.situation == .advantage(.me))

        state.scorePoint(for: .opponent)
        #expect(state.labels == "40:40")
        #expect(state.situation == .deuce)

        state.scorePoint(for: .opponent)
        #expect(state.labels == "40:AD")
        #expect(state.situation == .advantage(.opponent))
    }

    @Test func twoPointsInARowAfterDeuceWinTheGame() {
        var state = MatchState()
        state.score(.me, times: 3)
        state.score(.opponent, times: 3)
        // Long deuce battle
        for _ in 0..<5 {
            state.scorePoint(for: .me)
            state.scorePoint(for: .opponent)
        }
        #expect(state.games == .zero)
        state.scorePoint(for: .opponent)
        #expect(state.scorePoint(for: .opponent) == .game(.opponent))
        #expect(state.games == TeamScore(me: 0, opponent: 1))
    }
}

@Suite("Golden point")
struct GoldenPointTests {
    let rules = MatchRules(deuceRule: .goldenPoint)

    @Test func fortyAllIsGoldenPoint() {
        var state = MatchState(rules: rules)
        state.score(.me, times: 3)
        state.score(.opponent, times: 3)
        #expect(state.labels == "40:40")
        #expect(state.situation == .goldenPoint)
    }

    @Test func nextPointAtFortyAllWinsGame() {
        var state = MatchState(rules: rules)
        state.score(.me, times: 3)
        state.score(.opponent, times: 3)
        #expect(state.scorePoint(for: .opponent) == .game(.opponent))
        #expect(state.games == TeamScore(me: 0, opponent: 1))
        #expect(state.points == .zero)
    }

    @Test func normalGamesUnaffected() {
        var state = MatchState(rules: rules)
        state.score(.me, times: 3)
        state.scorePoint(for: .opponent)
        #expect(state.scorePoint(for: .me) == .game(.me))
    }
}

// MARK: - Sets

@Suite("Sets")
struct SetTests {
    @Test func sixGamesWithTwoGameMarginWinsSet() {
        var state = MatchState()
        state.winGames(.me, 4)
        state.winGames(.opponent, 4)
        state.winGame(.me)
        state.score(.me, times: 3)
        #expect(state.scorePoint(for: .me) == .set(.me))
        #expect(state.completedSets == [SetScore(games: TeamScore(me: 6, opponent: 4))])
        #expect(state.games == .zero)
        #expect(state.setsWon == TeamScore(me: 1, opponent: 0))
    }

    @Test func sixFiveIsNotEnough() {
        var state = MatchState()
        state.winGames(.me, 5)
        state.winGames(.opponent, 5)
        state.winGame(.me)
        #expect(state.games == TeamScore(me: 6, opponent: 5))
        #expect(state.completedSets.isEmpty)
        #expect(state.isTiebreak == false)
    }

    @Test func sevenFiveWinsSet() {
        var state = MatchState()
        state.winGames(.me, 5)
        state.winGames(.opponent, 5)
        state.winGame(.opponent)
        state.score(.opponent, times: 3)
        #expect(state.scorePoint(for: .opponent) == .set(.opponent))
        #expect(state.completedSets.last?.games == TeamScore(me: 5, opponent: 7))
        #expect(state.completedSets.last?.winner == .opponent)
    }
}

// MARK: - Tiebreak

@Suite("Tiebreak")
struct TiebreakTests {
    @Test func sixAllStartsTiebreak() {
        var state = MatchState()
        state.reachTiebreak()
        #expect(state.games == TeamScore(me: 6, opponent: 6))
        #expect(state.isTiebreak)
        #expect(state.situation == .tiebreak)
        #expect(state.labels == "0:0")
    }

    @Test func tiebreakCountsOneTwoThree() {
        var state = MatchState()
        state.reachTiebreak()
        state.score(.me, times: 3)
        state.scorePoint(for: .opponent)
        #expect(state.labels == "3:1")
        state.score(.me, times: 2)
        #expect(state.labels == "5:1")
    }

    @Test func tiebreakToSevenWinsSetSevenSix() {
        var state = MatchState()
        state.reachTiebreak()
        state.score(.me, times: 6)
        state.score(.opponent, times: 5)
        #expect(state.scorePoint(for: .me) == .set(.me))
        let set = try! #require(state.completedSets.first)
        #expect(set.games == TeamScore(me: 7, opponent: 6))
        #expect(set.tiebreak == TeamScore(me: 7, opponent: 5))
        #expect(state.isTiebreak == false)
        #expect(state.points == .zero)
    }

    @Test func tiebreakNeedsTwoPointMargin() {
        var state = MatchState()
        state.reachTiebreak()
        state.score(.me, times: 6)
        state.score(.opponent, times: 6)
        #expect(state.scorePoint(for: .me) == .point(.me))
        #expect(state.labels == "7:6")
        state.scorePoint(for: .opponent)
        state.scorePoint(for: .opponent)
        #expect(state.labels == "7:8")
        state.scorePoint(for: .me)
        state.scorePoint(for: .me)
        #expect(state.scorePoint(for: .me) == .set(.me))
        #expect(state.completedSets.first?.tiebreak == TeamScore(me: 10, opponent: 8))
    }

    @Test func noAdvantageLabelsInTiebreak() {
        var state = MatchState(rules: MatchRules(deuceRule: .goldenPoint))
        state.reachTiebreak()
        state.score(.me, times: 4)
        state.score(.opponent, times: 3)
        #expect(state.labels == "4:3")
    }
}

// MARK: - Match

@Suite("Match")
struct MatchTests {
    @Test func bestOfThreeEndsAfterTwoSets() {
        var state = MatchState()
        state.winSet(.me)
        state.winSet(.opponent)
        #expect(state.isFinished == false)
        state.winGames(.me, 5)
        state.score(.me, times: 3)
        #expect(state.scorePoint(for: .me) == .match(.me))
        #expect(state.winner == .me)
        #expect(state.setsWon == TeamScore(me: 2, opponent: 1))
    }

    @Test func pointsAfterMatchEndAreIgnored() {
        var state = MatchState()
        state.winSet(.opponent)
        state.winSet(.opponent)
        #expect(state.winner == .opponent)
        let finished = state
        #expect(state.scorePoint(for: .me) == nil)
        #expect(state == finished)
    }

    @Test(arguments: [(1, 1), (3, 2), (5, 3)])
    func setsNeededForBestOf(bestOf: Int, setsToWin: Int) {
        let rules = MatchRules(bestOf: bestOf)
        #expect(rules.setsToWin == setsToWin)
        var state = MatchState(rules: rules)
        for _ in 0..<(setsToWin - 1) { state.winSet(.me) }
        #expect(state.isFinished == false)
        state.winSet(.me)
        #expect(state.winner == .me)
    }

    @Test func setScoresIncludeRunningSet() {
        var state = MatchState()
        state.winSet(.me)
        state.winGames(.opponent, 2)
        state.scorePoint(for: .me)
        let sets = state.setScoresIncludingCurrent
        #expect(sets.count == 2)
        #expect(sets[1] == SetScore(games: TeamScore(me: 0, opponent: 2), isComplete: false))
        #expect(sets[1].winner == nil)
    }

    @Test func setScoresOfFinishedMatchAreOnlyCompletedSets() {
        var state = MatchState()
        state.winSet(.me)
        state.winSet(.me)
        #expect(state.setScoresIncludingCurrent.count == 2)
    }
}

// MARK: - Undo

@Suite("Undo")
struct UndoTests {
    @Test func nothingToUndoInitially() {
        var scorer = MatchScorer()
        #expect(scorer.canUndo == false)
        let undone = scorer.undo()
        #expect(undone == false)
    }

    @Test func undoRevertsLastPoint() {
        var scorer = MatchScorer()
        scorer.scorePoint(for: .me)
        scorer.scorePoint(for: .opponent)
        let undone = scorer.undo()
        #expect(undone)
        #expect(scorer.state.labels == "15:0")
        let undoneAgain = scorer.undo()
        #expect(undoneAgain)
        #expect(scorer.state == MatchState())
        #expect(scorer.canUndo == false)
    }

    @Test func undoAcrossGameBoundary() {
        var scorer = MatchScorer()
        for _ in 0..<3 { scorer.scorePoint(for: .me) }
        scorer.scorePoint(for: .opponent)
        #expect(scorer.scorePoint(for: .me) == .game(.me))
        scorer.undo()
        #expect(scorer.state.games == .zero)
        #expect(scorer.state.labels == "40:15")
    }

    @Test func undoAfterMatchWinReopensMatch() {
        var scorer = MatchScorer(rules: MatchRules(bestOf: 1))
        var outcome: PointOutcome?
        for _ in 0..<24 { outcome = scorer.scorePoint(for: .me) }
        #expect(outcome == .match(.me))
        #expect(scorer.state.isFinished)
        #expect(scorer.pointsPlayed == 24)

        scorer.undo()
        #expect(scorer.state.isFinished == false)
        #expect(scorer.state.games == TeamScore(me: 5, opponent: 0))
        #expect(scorer.state.labels == "40:0")
        #expect(scorer.scorePoint(for: .me) == .match(.me))
    }

    @Test func ignoredPointsDoNotCreateUndoSteps() {
        var scorer = MatchScorer(rules: MatchRules(bestOf: 1))
        for _ in 0..<24 { scorer.scorePoint(for: .opponent) }
        #expect(scorer.scorePoint(for: .me) == nil)
        #expect(scorer.pointsPlayed == 24)
    }

    @Test func resetAppliesNewRules() {
        var scorer = MatchScorer()
        scorer.scorePoint(for: .me)
        let rules = MatchRules(bestOf: 5, deuceRule: .goldenPoint)
        scorer.reset(rules: rules)
        #expect(scorer.rules == rules)
        #expect(scorer.canUndo == false)
        #expect(scorer.state.hasStarted == false)
    }
}

// MARK: - Persistence

@Suite("Codable")
struct CodableTests {
    @Test func scorerRoundTripsThroughJSON() throws {
        var scorer = MatchScorer(rules: MatchRules(bestOf: 5, deuceRule: .goldenPoint))
        for team in [Team.me, .me, .opponent, .me, .me, .opponent] {
            scorer.scorePoint(for: team)
        }
        let data = try JSONEncoder().encode(scorer)
        var decoded = try JSONDecoder().decode(MatchScorer.self, from: data)
        #expect(decoded == scorer)
        let undone = decoded.undo()
        #expect(undone)
        #expect(decoded.state.games == TeamScore(me: 1, opponent: 0))
    }
}

// MARK: - Serve

@Suite("Serve")
struct ServeTests {
    @Test func serveAlternatesEveryGame() {
        var state = MatchState()
        #expect(state.server == .me)
        state.scorePoint(for: .opponent)
        #expect(state.server == .me)
        state.winGame(.me)  // finishes game 1 (me 4 points, opponent 1)
        #expect(state.server == .opponent)
        state.winGame(.opponent)
        #expect(state.server == .me)
    }

    @Test func firstServerCanOnlyChangeBeforeFirstPoint() {
        var scorer = MatchScorer()
        let changed = scorer.setFirstServer(.opponent)
        #expect(changed)
        #expect(scorer.state.server == .opponent)
        #expect(scorer.canUndo == false)
        scorer.scorePoint(for: .me)
        let changedLater = scorer.setFirstServer(.me)
        #expect(changedLater == false)
        #expect(scorer.state.firstServer == .opponent)
    }

    @Test func undoRestoresServer() {
        var scorer = MatchScorer()
        for _ in 0..<4 { scorer.scorePoint(for: .me) }
        #expect(scorer.state.server == .opponent)
        scorer.undo()
        #expect(scorer.state.server == .me)
    }

    @Test func tiebreakServeAlternatesEveryTwoPoints() {
        var state = MatchState()
        state.reachTiebreak()  // 12 games played → first server is due
        var servers: [Team] = []
        for _ in 0..<6 {
            servers.append(state.server)
            state.scorePoint(for: .me)
            state.scorePoint(for: .opponent)
        }
        // Points 1…12: A, B B, A A, B B, A A, B B, A
        var expected: [Team] = []
        for point in 0..<12 {
            expected.append(((point + 1) / 2).isMultiple(of: 2) ? Team.me : .opponent)
        }
        #expect(servers == stride(from: 0, to: 12, by: 2).map { expected[$0] })
    }

    @Test func receiverOfTiebreakServesFirstInNextSet() {
        var state = MatchState()
        state.reachTiebreak()
        let tiebreakFirstServer = state.server
        state.score(.me, times: 7)
        #expect(state.completedSets.count == 1)
        #expect(state.server == tiebreakFirstServer.other)
    }
}

// MARK: - Side changes

@Suite("Side changes")
struct SideChangeTests {
    @Test func changeAfterOddGames() {
        var state = MatchState()
        state.score(.me, times: 3)
        let first = state.scorePoint(for: .me)!
        #expect(state.isSideChange(after: first))      // 1:0
        state.score(.opponent, times: 3)
        let second = state.scorePoint(for: .opponent)!
        #expect(state.isSideChange(after: second) == false) // 1:1
        state.score(.me, times: 3)
        let third = state.scorePoint(for: .me)!
        #expect(state.isSideChange(after: third))      // 2:1
    }

    @Test func noChangeOnNormalPoints() {
        var state = MatchState()
        let outcome = state.scorePoint(for: .me)!
        #expect(state.isSideChange(after: outcome) == false)
    }

    @Test func setEndingOnOddTotalChangesEnds() {
        var state = MatchState()
        state.winGames(.opponent, 3)
        state.winGames(.me, 5)
        state.score(.me, times: 3)
        let outcome = state.scorePoint(for: .me)!   // 6:3 → 9 games
        #expect(outcome == .set(.me))
        #expect(state.isSideChange(after: outcome))
    }

    @Test func setEndingOnEvenTotalDoesNotChangeEnds() {
        var state = MatchState()
        state.winGames(.opponent, 4)
        state.winGames(.me, 5)
        state.score(.me, times: 3)
        let outcome = state.scorePoint(for: .me)!   // 6:4 → 10 games
        #expect(outcome == .set(.me))
        #expect(state.isSideChange(after: outcome) == false)
    }

    @Test func tiebreakChangesEverySixPoints() {
        var state = MatchState()
        state.reachTiebreak()
        var changes: [Int] = []
        for point in 1...12 {
            let outcome = state.scorePoint(for: point.isMultiple(of: 2) ? .me : .opponent)!
            if state.isSideChange(after: outcome) { changes.append(point) }
        }
        #expect(changes == [6, 12])
    }
}

// MARK: - Set / match points

@Suite("Big points")
struct BigPointTests {
    @Test func setPointAtFiveLoveForty() {
        var state = MatchState()
        state.winGames(.me, 5)
        state.score(.me, times: 3)
        #expect(state.bigPoint(for: .me) == .setPoint)
        #expect(state.bigPoint(for: .opponent) == nil)
    }

    @Test func matchPointInLastSet() {
        var state = MatchState()
        state.winSet(.me)
        state.winGames(.me, 5)
        state.score(.me, times: 3)
        #expect(state.bigPoint(for: .me) == .matchPoint)
    }

    @Test func noBigPointEarlyInSet() {
        var state = MatchState()
        state.score(.me, times: 3)
        #expect(state.bigPoint(for: .me) == nil)
    }

    @Test func bothTeamsHaveSetPointInTiebreakAtSixAll() {
        var state = MatchState()
        state.reachTiebreak()
        state.score(.me, times: 6)
        state.score(.opponent, times: 6)
        #expect(state.bigPoint(for: .me) == nil)
        state.scorePoint(for: .me)
        #expect(state.bigPoint(for: .me) == .setPoint)
        #expect(state.bigPoint(for: .opponent) == nil)
    }

    @Test func bigPointCheckDoesNotChangeState() {
        var state = MatchState()
        state.winGames(.me, 5)
        state.score(.me, times: 3)
        let before = state
        _ = state.bigPoint(for: .me)
        #expect(state == before)
    }
}

// MARK: - Super tiebreak

@Suite("Super tiebreak")
struct SuperTiebreakTests {
    let rules = MatchRules(bestOf: 3, superTiebreak: true)

    @Test func oneSetAllStartsSuperTiebreak() {
        var state = MatchState(rules: rules)
        state.winSet(.me)
        #expect(state.isSuperTiebreak == false)
        state.winSet(.opponent)
        #expect(state.isSuperTiebreak)
        #expect(state.situation == .superTiebreak)
        state.score(.me, times: 3)
        #expect(state.pointLabel(for: .me) == "3")
    }

    @Test func superTiebreakToTenWinsMatch() {
        var state = MatchState(rules: rules)
        state.winSet(.me)
        state.winSet(.opponent)
        state.score(.me, times: 9)
        state.score(.opponent, times: 8)
        #expect(state.bigPoint(for: .me) == .matchPoint)
        #expect(state.scorePoint(for: .me) == .match(.me))
        let last = try! #require(state.completedSets.last)
        #expect(last.isSuperTiebreak)
        #expect(last.tiebreak == TeamScore(me: 10, opponent: 8))
        #expect(last.winner == .me)
        #expect(state.setsWon == TeamScore(me: 2, opponent: 1))
    }

    @Test func superTiebreakNeedsTwoPointMargin() {
        var state = MatchState(rules: rules)
        state.winSet(.me)
        state.winSet(.opponent)
        state.score(.me, times: 9)
        state.score(.opponent, times: 9)
        #expect(state.scorePoint(for: .opponent) == .point(.opponent))
        #expect(state.pointLabel(for: .opponent) == "10")
        state.scorePoint(for: .me)
        state.scorePoint(for: .me)
        #expect(state.scorePoint(for: .me) == .match(.me))
    }

    @Test func notUsedWhenDisabled() {
        var state = MatchState()
        state.winSet(.me)
        state.winSet(.opponent)
        #expect(state.isSuperTiebreak == false)
        state.score(.me, times: 4)
        #expect(state.games == TeamScore(me: 1, opponent: 0))
    }

    @Test func neverInBestOfOne() {
        let state = MatchState(rules: MatchRules(bestOf: 1, superTiebreak: true))
        #expect(state.isSuperTiebreak == false)
    }

    @Test func bestOfFiveAtTwoAll() {
        var state = MatchState(rules: MatchRules(bestOf: 5, superTiebreak: true))
        state.winSet(.me)
        state.winSet(.opponent)
        state.winSet(.me)
        #expect(state.isSuperTiebreak == false)
        state.winSet(.opponent)
        #expect(state.isSuperTiebreak)
    }

    @Test func runningSuperTiebreakAppearsInSetScores() {
        var state = MatchState(rules: rules)
        state.winSet(.me)
        state.winSet(.opponent)
        state.score(.opponent, times: 4)
        let running = try! #require(state.setScoresIncludingCurrent.last)
        #expect(running.isSuperTiebreak)
        #expect(running.isComplete == false)
        #expect(running.tiebreak == TeamScore(me: 0, opponent: 4))
    }
}

// MARK: - Backwards compatibility

@Suite("Legacy data")
struct LegacyDecodingTests {
    @Test func decodesStateSavedBeforeServeAndSuperTiebreak() throws {
        let json = """
        {"rules":{"bestOf":3,"deuceRule":"advantage","gamesPerSet":6,"tiebreakPoints":7},
         "completedSets":[{"games":{"me":6,"opponent":4},"isComplete":true}],
         "games":{"me":2,"opponent":1},"points":{"me":1,"opponent":0}}
        """
        let state = try JSONDecoder().decode(MatchState.self, from: Data(json.utf8))
        #expect(state.rules.superTiebreak == false)
        #expect(state.firstServer == .me)
        #expect(state.completedSets.first?.isSuperTiebreak == false)
        #expect(state.games == TeamScore(me: 2, opponent: 1))
    }

    @Test func decodesLegacySetList() throws {
        let json = #"[{"games":{"me":7,"opponent":6},"tiebreak":{"me":7,"opponent":4},"isComplete":true}]"#
        let sets = try JSONDecoder().decode([SetScore].self, from: Data(json.utf8))
        #expect(sets.first?.tiebreak == TeamScore(me: 7, opponent: 4))
        #expect(sets.first?.isSuperTiebreak == false)
    }
}
