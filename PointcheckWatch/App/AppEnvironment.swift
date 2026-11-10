import SwiftData

/// Process-wide objects shared by the UI and the Siri / App Intents.
///
/// Both the SwiftUI scene and the intents must talk to the *same* running match,
/// so the container and controller are created once, lazily, on the main actor.
@MainActor
enum AppEnvironment {
    static let container: ModelContainer = {
        AppSettings.registerDefaults()
        do {
            return try ModelContainer(for: MatchRecord.self)
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    static let controller = MatchController(
        repository: MatchRepository(context: container.mainContext),
        workout: WorkoutManager()
    )
}
