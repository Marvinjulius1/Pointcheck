import SwiftData
import SwiftUI

@main
struct PointcheckApp: App {
    @State private var controller = AppEnvironment.controller

    init() {
        PhoneSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScoreboardView()
            }
            .environment(controller)
            .tint(Theme.me)
        }
        .modelContainer(AppEnvironment.container)
    }
}
