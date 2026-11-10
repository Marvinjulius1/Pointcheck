import Foundation

/// Training data of one workout (from Apple Health), independent of HealthKit types.
public struct WorkoutMetrics: Hashable, Sendable {
    public var start: Date
    public var end: Date
    /// Active energy in kilocalories.
    public var activeEnergy: Double?
    /// Beats per minute.
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?

    public init(start: Date, end: Date, activeEnergy: Double? = nil, averageHeartRate: Double? = nil, maxHeartRate: Double? = nil) {
        self.start = start
        self.end = end
        self.activeEnergy = activeEnergy
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Totals over all matches that have training data.
public struct HealthTotals: Hashable, Sendable {
    public var matchesWithData: Int
    public var activeEnergy: Double
    /// Average of the per-match average heart rates.
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
}

extension PadelStats {
    /// Pairs each match with the workout that overlaps it the most.
    ///
    /// The watch starts the workout with the first point and ends it with the match,
    /// so both intervals almost coincide. Matches without an end date are assumed to
    /// last at most `openMatchLength`. Each workout is used for one match only.
    public static func assignWorkouts(
        _ workouts: [WorkoutMetrics],
        to matches: [MatchSummary],
        openMatchLength: TimeInterval = 3 * 3600
    ) -> [UUID: WorkoutMetrics] {
        var candidates: [(match: UUID, workout: Int, overlap: TimeInterval)] = []
        for match in matches {
            let matchEnd = match.endDate ?? match.startDate.addingTimeInterval(openMatchLength)
            for (index, workout) in workouts.enumerated() {
                let overlap = min(matchEnd, workout.end).timeIntervalSince(max(match.startDate, workout.start))
                if overlap > 0 { candidates.append((match.id, index, overlap)) }
            }
        }
        // Greedy by largest overlap: best pairs first, no workout or match used twice.
        var result: [UUID: WorkoutMetrics] = [:]
        var usedWorkouts = Set<Int>()
        for candidate in candidates.sorted(by: { $0.overlap > $1.overlap }) {
            guard result[candidate.match] == nil, !usedWorkouts.contains(candidate.workout) else { continue }
            result[candidate.match] = workouts[candidate.workout]
            usedWorkouts.insert(candidate.workout)
        }
        return result
    }

    public static func healthTotals(_ metrics: some Collection<WorkoutMetrics>) -> HealthTotals {
        let heartRates = metrics.compactMap(\.averageHeartRate)
        return HealthTotals(
            matchesWithData: metrics.count,
            activeEnergy: metrics.compactMap(\.activeEnergy).reduce(0, +),
            averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
            maxHeartRate: metrics.compactMap(\.maxHeartRate).max()
        )
    }
}
