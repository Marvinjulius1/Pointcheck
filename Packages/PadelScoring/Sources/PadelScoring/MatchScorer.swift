/// Drives a match and keeps a full undo history.
///
/// Every point stores a snapshot of the previous state, so mistaken taps can be
/// reverted step by step – across game, set and even match boundaries.
public struct MatchScorer: Codable, Hashable, Sendable {
    public private(set) var state: MatchState
    private var history: [MatchState] = []

    public init(rules: MatchRules = .standard) {
        state = MatchState(rules: rules)
    }

    public var rules: MatchRules { state.rules }
    public var canUndo: Bool { !history.isEmpty }
    public var pointsPlayed: Int { history.count }

    @discardableResult
    public mutating func scorePoint(for team: Team) -> PointOutcome? {
        let previous = state
        guard let outcome = state.scorePoint(for: team) else { return nil }
        history.append(previous)
        return outcome
    }

    /// Reverts the last point. Returns `false` if there was nothing to undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        return true
    }

    /// Starts a fresh match with the given rules.
    public mutating func reset(rules: MatchRules) {
        self = MatchScorer(rules: rules)
    }
}
