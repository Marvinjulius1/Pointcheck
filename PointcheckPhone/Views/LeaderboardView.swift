import PadelStats
import SwiftUI

struct LeaderboardView: View {
    @Environment(AccountService.self) private var account
    @State private var rows: [LeaderboardRow] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && rows.isEmpty {
                ContentUnavailableView(
                    "Noch keine Rangliste",
                    systemImage: "trophy",
                    description: Text("Hier erscheinen öffentliche Profile mit mindestens einem bestätigten Match.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text("\(index + 1).")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    LevelBadge(level: row.level, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName).font(.body.weight(row.id == account.userID ? .bold : .regular))
                        Text("\(row.ratedMatches) Matches").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(row.rating.rounded()))").font(Theme.scoreFont(size: 17))
                }
                .listRowBackground(row.id == account.userID ? Theme.surface : nil)
            }
        }
        .navigationTitle("Rangliste")
        .task {
            rows = await account.leaderboard()
            loaded = true
        }
        .refreshable { rows = await account.leaderboard() }
    }
}
