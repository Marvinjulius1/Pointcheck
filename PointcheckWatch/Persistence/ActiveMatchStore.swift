import Foundation
import PadelScoring

/// Keeps the running match (including its undo history) across app launches.
struct ActiveMatchStore {
    struct Snapshot: Codable {
        var scorer: MatchScorer
        var recordID: UUID?
    }

    private let defaults: UserDefaults
    private let key = "activeMatch.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
