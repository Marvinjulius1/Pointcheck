import Foundation
import Observation
import PadelScoring

/// Short-lived visual feedback after a point.
struct Highlight: Equatable {
    enum Kind: Equatable {
        case game, set, match, undo
    }

    let kind: Kind
    let team: Team?
    let id = UUID()

    var title: String {
        switch kind {
        case .game: "Spiel"
        case .set: "Satz"
        case .match: "Match"
        case .undo: "Rückgängig"
        }
    }
}

/// The single source of truth for the running match.
/// Glues together scoring logic, persistence, haptics and the workout session.
@Observable
@MainActor
final class MatchController {
    private(set) var scorer: MatchScorer
    private(set) var highlight: Highlight?
    /// Shown for a few seconds after a point that requires the teams to change ends.
    private(set) var showsSideChange = false

    var state: MatchState { scorer.state }

    private let repository: MatchRepository
    private let activeStore: ActiveMatchStore
    let workout: WorkoutManager
    @ObservationIgnored private var recordID: UUID?
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    @ObservationIgnored private var sideChangeTask: Task<Void, Never>?

    init(repository: MatchRepository, activeStore: ActiveMatchStore = ActiveMatchStore(), workout: WorkoutManager) {
        self.repository = repository
        self.activeStore = activeStore
        self.workout = workout

        if let snapshot = activeStore.load() {
            scorer = snapshot.scorer
            recordID = snapshot.recordID
        } else {
            scorer = MatchScorer(rules: AppSettings.currentRules())
        }
    }

    // MARK: - Actions

    func score(_ team: Team) {
        guard let outcome = scorer.scorePoint(for: team) else {
            Haptics.rejected()
            return
        }
        Haptics.play(for: outcome)

        switch outcome {
        case .point: break
        case .game(let team): show(Highlight(kind: .game, team: team))
        case .set(let team): show(Highlight(kind: .set, team: team))
        case .match(let team): show(Highlight(kind: .match, team: team), duration: 2.5)
        }

        if state.isSideChange(after: outcome) {
            showSideChange()
        }

        persist()

        if case .match = outcome {
            workout.end()
        } else if AppSettings.recordsWorkout() {
            workout.startIfNeeded()
        }
    }

    func undo() {
        guard scorer.undo() else {
            Haptics.rejected()
            return
        }
        Haptics.undo()
        hideSideChange()
        show(Highlight(kind: .undo, team: nil), duration: 0.8)
        persist()
        if !state.hasStarted {
            workout.discard()
        }
    }

    /// Saves the current match to the history and starts a fresh one.
    func startNewMatch() {
        if let recordID, state.hasStarted {
            repository.complete(id: recordID)
        }
        workout.end()
        recordID = nil
        scorer = MatchScorer(rules: AppSettings.currentRules())
        highlight = nil
        hideSideChange()
        Haptics.newMatch()
        persist()
    }

    /// Applies changed settings right away, as long as no point has been played.
    func settingsDidChange() {
        guard !state.hasStarted else { return }
        scorer.reset(rules: AppSettings.currentRules(), firstServer: state.firstServer)
        persist()
    }

    /// Before the first point: hands the serve to the other team.
    func toggleFirstServer() {
        guard scorer.setFirstServer(state.firstServer.other) else { return }
        Haptics.serveChanged()
        persist()
    }

    /// Short spoken/visual summary, e.g. for Siri: "30 zu 15".
    var scoreSummary: String {
        if let winner = state.winner {
            return winner == .me ? "Match gewonnen!" : "Match verloren."
        }
        return "\(state.pointLabel(for: .me)) zu \(state.pointLabel(for: .opponent))"
    }

    var settingsDifferFromCurrentMatch: Bool {
        state.hasStarted && scorer.rules != AppSettings.currentRules()
    }

    // MARK: - Private

    private func persist() {
        recordID = repository.sync(state, recordID: recordID)
        activeStore.save(.init(scorer: scorer, recordID: recordID))
    }

    private func showSideChange() {
        sideChangeTask?.cancel()
        showsSideChange = true
        Haptics.sideChange()
        sideChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.showsSideChange = false
        }
    }

    private func hideSideChange() {
        sideChangeTask?.cancel()
        showsSideChange = false
    }

    private func show(_ highlight: Highlight, duration: TimeInterval = 1.4) {
        highlightTask?.cancel()
        self.highlight = highlight
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.highlight = nil
        }
    }
}
