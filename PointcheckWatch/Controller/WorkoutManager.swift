import Foundation
import HealthKit
import Observation

/// Runs an HKWorkoutSession while a match is being played.
///
/// An active workout session keeps the app in the foreground on wrist raise
/// (screen stays on the scoreboard) and records the match as a training in Health.
@Observable
@MainActor
final class WorkoutManager: NSObject {
    private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    /// Padel has no dedicated HealthKit type; tennis is the closest match.
    private static let activityType: HKWorkoutActivityType = .tennis

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }

    /// Starts a workout if none is running.
    func startIfNeeded() {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType
        configuration.locationType = .unknown

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, error in
                if let error { print("Workout collection failed: \(error)") }
            }
            isRunning = true
        } catch {
            print("Could not start workout: \(error)")
        }
    }

    /// Ends the running workout and saves it to Health.
    func end() {
        guard let session else { return }
        session.end() // finishing happens in the delegate once the session has ended
    }

    /// Ends the workout without saving it (e.g. match undone back to zero).
    func discard() {
        guard let session else { return }
        let builder = self.builder
        reset()
        session.end()
        builder?.discardWorkout()
    }

    private func finish(builder: HKLiveWorkoutBuilder) {
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.finishWorkout { _, error in
                if let error { print("Saving workout failed: \(error)") }
            }
        }
    }

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        Task { @MainActor in
            // Only finish the session we still own (discard() already released it).
            guard workoutSession === self.session, let builder = self.builder else { return }
            self.reset()
            self.finish(builder: builder)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
        Task { @MainActor in
            if workoutSession === self.session { self.reset() }
        }
    }
}
