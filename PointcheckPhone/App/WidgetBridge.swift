import Foundation
import PadelStats
import WidgetKit

/// Feeds the home-screen widgets with the current rating and the next planned match.
@MainActor
enum WidgetBridge {
    static func update(account: AccountService, matches: [MatchSummary]) {
        let now = Date.now
        let points: [RatingPoint]
        let current: Double
        if let profile = account.profile, let first = account.ratingHistory.first {
            points = [RatingPoint(date: first.createdAt.addingTimeInterval(-1), rating: first.ratingBefore)]
                + account.ratingHistory.map { RatingPoint(date: $0.createdAt, rating: $0.ratingAfter) }
            current = profile.rating
        } else {
            let report = PadelStats.localRatings(matches)
            points = report.history.map { RatingPoint(date: $0.date, rating: $0.rating) }
            current = report.me.rating
        }
        let window = RatingSeries.window(points, current: current, since: now.addingTimeInterval(-30 * 86_400), now: now)
        let change = RatingSeries.change(window)

        // Next planned match: accepted rematch in the future.
        let next = account.rematches
            .filter { $0.status == .accepted && $0.proposedAt > now }
            .min { $0.proposedAt < $1.proposedAt }

        WidgetSnapshot(
            rating: current,
            level: PadelLevel.level(for: current),
            change30d: change.delta,
            points: window.map { WidgetSnapshot.Point(date: $0.date, rating: $0.rating) },
            nextGameTitle: next.map { "Revanche mit \($0.otherName)" },
            nextGameDate: next?.proposedAt,
            updatedAt: now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
