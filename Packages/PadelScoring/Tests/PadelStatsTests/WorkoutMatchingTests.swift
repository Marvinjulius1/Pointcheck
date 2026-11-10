import Foundation
import Testing
@testable import PadelStats

@Suite("Workout matching")
struct WorkoutMatchingTests {
    let t0 = Date(timeIntervalSince1970: 1_767_265_200) // 2026-01-01 11:00 UTC

    func minutes(_ value: Double) -> Date { t0.addingTimeInterval(value * 60) }

    func match(_ start: Double, _ end: Double?) -> MatchSummary {
        MatchSummary(startDate: minutes(start), endDate: end.map(minutes), winner: .me)
    }

    @Test func pairsOverlappingWorkout() {
        let m = match(0, 90)
        let workouts = [
            WorkoutMetrics(start: minutes(-300), end: minutes(-240), activeEnergy: 100),
            WorkoutMetrics(start: minutes(1), end: minutes(91), activeEnergy: 650, averageHeartRate: 142, maxHeartRate: 178),
        ]
        let result = PadelStats.assignWorkouts(workouts, to: [m])
        #expect(result[m.id]?.activeEnergy == 650)
    }

    @Test func noOverlapNoData() {
        let m = match(0, 60)
        let workouts = [WorkoutMetrics(start: minutes(120), end: minutes(180))]
        #expect(PadelStats.assignWorkouts(workouts, to: [m]).isEmpty)
    }

    @Test func eachWorkoutUsedOnce() {
        // Two back-to-back matches, one long workout covering mostly the first one.
        let first = match(0, 60)
        let second = match(60, 120)
        let workouts = [
            WorkoutMetrics(start: minutes(0), end: minutes(70), activeEnergy: 1),
            WorkoutMetrics(start: minutes(61), end: minutes(119), activeEnergy: 2),
        ]
        let result = PadelStats.assignWorkouts(workouts, to: [first, second])
        #expect(result[first.id]?.activeEnergy == 1)
        #expect(result[second.id]?.activeEnergy == 2)
    }

    @Test func openMatchUsesAssumedLength() {
        let m = match(0, nil)
        let workouts = [WorkoutMetrics(start: minutes(30), end: minutes(100), activeEnergy: 5)]
        #expect(PadelStats.assignWorkouts(workouts, to: [m])[m.id]?.activeEnergy == 5)
    }

    @Test func totals() {
        let metrics = [
            WorkoutMetrics(start: minutes(0), end: minutes(60), activeEnergy: 500, averageHeartRate: 140, maxHeartRate: 170),
            WorkoutMetrics(start: minutes(100), end: minutes(160), activeEnergy: 300, averageHeartRate: 120, maxHeartRate: 181),
            WorkoutMetrics(start: minutes(200), end: minutes(260)),
        ]
        let totals = PadelStats.healthTotals(metrics)
        #expect(totals.matchesWithData == 3)
        #expect(totals.activeEnergy == 800)
        #expect(totals.averageHeartRate == 130)
        #expect(totals.maxHeartRate == 181)
    }

    @Test func emptyTotals() {
        let totals = PadelStats.healthTotals([WorkoutMetrics]())
        #expect(totals.averageHeartRate == nil)
        #expect(totals.activeEnergy == 0)
    }
}
