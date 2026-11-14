import Foundation
import UIKit
import UserNotifications

/// Asks for notification permission and registers the device token with the server.
/// Delivery of remote notifications needs the push entitlement (Apple Developer Program);
/// until then this only stores the token and prepares the ground.
@MainActor
final class PushManager: NSObject {
    static let shared = PushManager()
    static let enabledKey = "push.enabled"

    func enable() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Re-register on launch if the person switched notifications on.
    func registerIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PhoneEnvironment.account.registerDeviceToken(token) }
    }
}

/// Receives the APNs token (and failures, which are expected without the entitlement).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration not available yet: \(error.localizedDescription)")
    }
}
