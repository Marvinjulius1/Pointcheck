import PadelStats
import SwiftData
import SwiftUI

/// Achievements grid, shown inside the profile's "Erfolge" tab.
struct BadgesGrid: View {
    @Query private var stored: [StoredMatch]
    @Environment(AccountService.self) private var account

    var body: some View {
        let badges = PadelStats.badges(account.allMatches(local: stored.map(\.summary)))
        let unlocked = badges.filter(\.isUnlocked).count
        VStack(alignment: .leading, spacing: 14) {
            Card {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color(.tertiarySystemFill), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: Double(unlocked) / Double(max(badges.count, 1)))
                            .stroke(Theme.me.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.smooth, value: unlocked)
                        Text("\(unlocked)")
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(unlocked) von \(badges.count) Erfolgen")
                            .font(.headline)
                        Text(unlocked == badges.count ? "Alles freigeschaltet. Stark!" : "Spiel weiter – der nächste Erfolg wartet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(badges) { BadgeTile(badge: $0) }
            }
        }
    }
}

private struct BadgeTile: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: badge.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(badge.isUnlocked ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 58, height: 58)
                .background(badge.isUnlocked ? AnyShapeStyle(Theme.me.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .circle)
                .symbolEffect(.bounce, value: badge.isUnlocked)
            Text(badge.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
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
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
