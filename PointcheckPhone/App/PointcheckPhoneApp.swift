import SwiftData
import SwiftUI

@MainActor
enum PhoneEnvironment {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: StoredMatch.self)
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    static let sync = WatchSync(store: MatchStore(context: container.mainContext))
    static let health = HealthService()
}

@main
struct PointcheckPhoneApp: App {
    @State private var sync = PhoneEnvironment.sync
    @State private var health = PhoneEnvironment.health

    init() {
        PhoneEnvironment.sync.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .environment(health)
                .tint(Theme.me)
        }
        .modelContainer(PhoneEnvironment.container)
    }
}
