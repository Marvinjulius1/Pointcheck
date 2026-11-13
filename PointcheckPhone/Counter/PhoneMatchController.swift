import Foundation
import Observation
import PadelStats
import UIKit

/// Counting on the iPhone – same scoring logic as the watch, without a watch.
/// The running match survives app restarts; a finished match is stored like a watch match.
@Observable
@MainActor
final class PhoneMatchController {
    private(set) var scorer: MatchScorer
    private(set) var highlight: Highlight?
    private(set) var showsSideChange = false
    private(set) var startDate: Date
    /// Set once the finished match was saved (to show the names sheet only once).
    private(set) var isSaved = false

    var state: MatchState { scorer.state }

    private let store: MatchStore
    private var matchID: UUID
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    @ObservationIgnored private var sideChangeTask: Task<Void, Never>?

    private static let snapshotKey = "phone.activeMatch.v1"

    struct Highlight: Equatable {
        enum Kind { case game, set, match, undo }
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

    private struct Snapshot: Codable {
        var scorer: MatchScorer
        var matchID: UUID
        var startDate: Date
        var isSaved: Bool
    }

    init(store: MatchStore) {
        self.store = store
        if let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            scorer = snapshot.scorer
            matchID = snapshot.matchID
            startDate = snapshot.startDate
            isSaved = snapshot.isSaved
        } else {
            scorer = MatchScorer(rules: PhoneRules.current())
            matchID = UUID()
            startDate = .now
        }
    }

    // MARK: - Actions

    func score(_ team: Team) {
        guard let outcome = scorer.scorePoint(for: team) else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        if scorer.pointsPlayed == 1 { startDate = .now }
        switch outcome {
        case .point:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .game(let team):
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            show(Highlight(kind: .game, team: team))
        case .set(let team):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show(Highlight(kind: .set, team: team))
        case .match(let team):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show(Highlight(kind: .match, team: team), duration: 2.5)
        }
        if state.isSideChange(after: outcome) { showSideChange() }
        persist()
    }

    func undo() {
        guard scorer.undo() else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        hideSideChange()
        show(Highlight(kind: .undo, team: nil), duration: 0.8)
        if isSaved {
            // The match is open again – remove the stored copy until it is finished once more.
            store.delete(ids: [matchID])
            isSaved = false
        }
        persist()
    }

    func toggleFirstServer() {
        guard scorer.setFirstServer(state.firstServer.other) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        persist()
    }

    /// Stores the finished match with the names and clears the counter.
    func finish(partner: String, opponent: String) {
        guard state.isFinished else { return }
        store.upsert([summary(partner: partner, opponent: opponent)])
        isSaved = true
        reset()
    }

    /// Drops the running match without saving it.
    func discard() {
        reset()
    }

    func applyRules() {
        guard !state.hasStarted else { return }
        scorer.reset(rules: PhoneRules.current(), firstServer: state.firstServer)
        persist()
    }

    var scoreSummary: String {
        if let winner = state.winner { return winner == .me ? "Match gewonnen!" : "Match verloren." }
        return "\(state.pointLabel(for: .me)) zu \(state.pointLabel(for: .opponent))"
    }

    // MARK: - Private

    private func summary(partner: String, opponent: String) -> MatchSummary {
        MatchSummary(
            id: matchID,
            startDate: startDate,
            endDate: .now,
            opponentName: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
            partnerName: partner.trimmingCharacters(in: .whitespacesAndNewlines),
            sets: state.completedSets,
            winner: state.winner,
            isCompleted: true,
            bestOf: state.rules.bestOf,
            goldenPoint: state.rules.deuceRule == .goldenPoint,
            superTiebreak: state.rules.superTiebreak
        )
    }

    private func reset() {
        scorer = MatchScorer(rules: PhoneRules.current())
        highlight = nil
        hideSideChange()
        isSaved = false
        startDate = .now
        matchID = UUID()
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
    }

    private func persist() {
        let snapshot = Snapshot(scorer: scorer, matchID: matchID, startDate: startDate, isSaved: isSaved)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
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

    private func showSideChange() {
        sideChangeTask?.cancel()
        showsSideChange = true
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
}

/// Match rules for counting on the iPhone (independent of the watch's settings).
enum PhoneRules {
    static let bestOfKey = "phone.rules.bestOf"
    static let goldenPointKey = "phone.rules.goldenPoint"
    static let superTiebreakKey = "phone.rules.superTiebreak"

    static func current(_ defaults: UserDefaults = .standard) -> MatchRules {
        let bestOf = defaults.object(forKey: bestOfKey) as? Int ?? 3
        return MatchRules(
            bestOf: bestOf,
            deuceRule: defaults.bool(forKey: goldenPointKey) ? .goldenPoint : .advantage,
            superTiebreak: defaults.bool(forKey: superTiebreakKey)
        )
    }
}
