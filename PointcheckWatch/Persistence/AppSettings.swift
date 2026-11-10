import Foundation
import PadelScoring

/// UserDefaults keys shared by `@AppStorage` in the views and the controller.
enum AppSettings {
    static let bestOfKey = "settings.bestOf"
    static let goldenPointKey = "settings.goldenPoint"
    static let recordWorkoutKey = "settings.recordWorkout"
    static let superTiebreakKey = "settings.superTiebreak"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            bestOfKey: 3,
            goldenPointKey: false,
            recordWorkoutKey: true,
            superTiebreakKey: false,
        ])
    }

    static func currentRules(_ defaults: UserDefaults = .standard) -> MatchRules {
        MatchRules(
            bestOf: defaults.integer(forKey: bestOfKey),
            deuceRule: defaults.bool(forKey: goldenPointKey) ? .goldenPoint : .advantage,
            superTiebreak: defaults.bool(forKey: superTiebreakKey)
        )
    }

    static func recordsWorkout(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: recordWorkoutKey)
    }
}
