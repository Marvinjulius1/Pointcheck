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
    static let counter = PhoneMatchController(store: MatchStore(context: container.mainContext))
    static let badges = BadgeTracker()
}

@main
struct PointcheckPhoneApp: App {
    @State private var sync = PhoneEnvironment.sync
    @State private var health = PhoneEnvironment.health
    @State private var account = PhoneEnvironment.account
    @State private var counter = PhoneEnvironment.counter
    @State private var badges = PhoneEnvironment.badges

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        PhoneEnvironment.sync.activate()
        PhoneEnvironment.account.start()
        PushManager.shared.registerIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environment(sync)
                .environment(health)
                .environment(account)
                .environment(counter)
                .environment(badges)
                .onOpenURL { url in
                    Task { await account.handleOpenURL(url) }
                }
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .modelContainer(PhoneEnvironment.container)
    }
}
