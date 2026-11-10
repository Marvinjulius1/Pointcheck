import Foundation
import HealthKit
import Observation
import PadelStats

/// Reads the tennis workouts the watch recorded for each match (heart rate, energy).
///
/// The watch saves every match as a workout; Health syncs it to the iPhone by itself.
@Observable
@MainActor
final class HealthService {
    /// Training data per match id.
    private(set) var metrics: [UUID: WorkoutMetrics] = [:]
    private(set) var isLoading = false
    /// The permission sheet was shown once (HealthKit never reveals read permission).
    private(set) var hasRequestedAccess = UserDefaults.standard.bool(forKey: HealthService.requestedKey)

    @ObservationIgnored private let store = HKHealthStore()
    private static let requestedKey = "health.didRequestAccess"

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
        hasRequestedAccess = true
        UserDefaults.standard.set(true, forKey: Self.requestedKey)
    }

    /// Loads workouts in the time span of the given matches and assigns them.
    func refresh(for matches: [MatchSummary]) async {
        guard isAvailable, hasRequestedAccess,
              let earliest = matches.map(\.startDate).min() else {
            metrics = [:]
            return
        }
        isLoading = true
        defer { isLoading = false }

        let span = HKQuery.predicateForSamples(
            withStart: earliest.addingTimeInterval(-3600),
            end: .now,
            options: []
        )
        let tennis = HKQuery.predicateForWorkouts(with: .tennis)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: [span, tennis]))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let workouts = try await descriptor.result(for: store)
            metrics = PadelStats.assignWorkouts(workouts.map(Self.metrics(of:)), to: matches)
        } catch {
            print("Loading workouts failed: \(error)")
        }
    }

    private static func metrics(of workout: HKWorkout) -> WorkoutMetrics {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))
        return WorkoutMetrics(
            start: workout.startDate,
            end: workout.endDate,
            activeEnergy: energy?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
            maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm)
        )
    }
}
