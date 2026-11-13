import Foundation
import Observation
import PadelStats

/// Notices newly unlocked badges (for the celebration card and the green dot).
@Observable
@MainActor
final class BadgeTracker {
    /// Badge to celebrate right now, if any.
    private(set) var celebrating: Badge?
    /// New badges the person has not looked at in the Erfolge tab yet.
    private(set) var hasUnseen: Bool = UserDefaults.standard.bool(forKey: BadgeTracker.unseenKey)

    private static let seenKey = "badges.unlockedSeen"
    private static let unseenKey = "badges.hasUnseen"
    private var queue: [Badge] = []

    /// Call whenever the match list changed.
    func check(_ matches: [MatchSummary]) {
        let unlocked = PadelStats.badges(matches).filter(\.isUnlocked)
        var seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        if seen.isEmpty, !unlocked.isEmpty, !UserDefaults.standard.bool(forKey: "badges.initialised") {
            // First launch with existing history: don't celebrate everything at once.
            seen = Set(unlocked.map(\.id))
            UserDefaults.standard.set(true, forKey: "badges.initialised")
            UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
            return
        }
        UserDefaults.standard.set(true, forKey: "badges.initialised")
        let fresh = unlocked.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh.map(\.id))
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
        hasUnseen = true
        UserDefaults.standard.set(true, forKey: Self.unseenKey)
        queue.append(contentsOf: fresh)
        if celebrating == nil { showNext() }
    }

    func dismissCelebration() {
        celebrating = nil
        showNext()
    }

    /// The Erfolge tab was opened.
    func markSeen() {
        hasUnseen = false
        UserDefaults.standard.set(false, forKey: Self.unseenKey)
    }

    private func showNext() {
        guard celebrating == nil, !queue.isEmpty else { return }
        celebrating = queue.removeFirst()
    }
}
