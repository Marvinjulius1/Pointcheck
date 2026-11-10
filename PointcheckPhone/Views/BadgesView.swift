import PadelStats
import SwiftData
import SwiftUI

struct BadgesView: View {
    @Query private var stored: [StoredMatch]
    @Environment(AccountService.self) private var account

    var body: some View {
        let badges = PadelStats.badges(account.allMatches(local: stored.map(\.summary)))
        let unlocked = badges.filter(\.isUnlocked).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(unlocked) von \(badges.count) freigeschaltet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(badges) { BadgeTile(badge: $0) }
                }
            }
            .padding()
        }
        .navigationTitle("Erfolge")
    }
}

private struct BadgeTile: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: badge.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(badge.isUnlocked ? Theme.ball : .secondary)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(badge.isUnlocked ? Theme.me.opacity(0.45) : .clear), in: .circle)
                .symbolEffect(.bounce, value: badge.isUnlocked)
            Text(badge.title)
                .font(.headline)
            Text(badge.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !badge.isUnlocked {
                ProgressView(value: badge.progress)
                    .tint(Theme.me)
                Text("\(badge.current) / \(badge.target)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .opacity(badge.isUnlocked ? 1 : 0.75)
        .accessibilityElement(children: .combine)
    }
}
