import SwiftData
import SwiftUI

@main
struct PointcheckApp: App {
    private let container: ModelContainer
    @State private var controller: MatchController

    init() {
        AppSettings.registerDefaults()

        let container: ModelContainer
        do {
            container = try ModelContainer(for: MatchRecord.self)
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
        self.container = container

        _controller = State(initialValue: MatchController(
            repository: MatchRepository(context: container.mainContext),
            workout: WorkoutManager()
        ))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScoreboardView()
            }
            .environment(controller)
            .tint(Theme.me)
        }
        .modelContainer(container)
    }
}
