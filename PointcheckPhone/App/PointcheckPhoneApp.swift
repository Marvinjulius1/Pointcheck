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
    static let account = AccountService()
}

@main
struct PointcheckPhoneApp: App {
    @State private var sync = PhoneEnvironment.sync
    @State private var health = PhoneEnvironment.health
    @State private var account = PhoneEnvironment.account

    init() {
        PhoneEnvironment.sync.activate()
        PhoneEnvironment.account.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .environment(health)
                .environment(account)
                .tint(Theme.me)
        }
        .modelContainer(PhoneEnvironment.container)
    }
}
