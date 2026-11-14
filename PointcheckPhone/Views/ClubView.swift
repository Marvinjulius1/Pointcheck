import SwiftUI

/// Home club page: activity, ranking, open games.
struct ClubView: View {
    let club: String
    @Environment(AccountService.self) private var account
    @State private var ranking: [ClubMember] = []
    @State private var activity: ClubActivity?
    @State private var games: [GameWanted] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                    .padding(.horizontal, 20)
                    .revealOnAppear()

                if !games.isEmpty {
                    SectionTitle("Spieler gesucht") {
                        NavigationLink("Alle") { GamesWantedView(club: club) }
                    }
                    .padding(.horizontal, 16)
                    ForEach(games.prefix(3)) { game in
                        GameRow(game: game) { await load() }
                        FeedDivider()
                    }
                }

                SectionTitle("Rangliste") {
                    if games.isEmpty {
                        NavigationLink("Spieler suchen") { GamesWantedView(club: club) }
                    }
                }
                .padding(.horizontal, 16)
                if isLoading && ranking.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                } else if ranking.isEmpty {
                    EmptyState(symbol: "building.2", title: "Noch niemand in dieser Halle",
                               message: "Trag „\(club)“ als Heimat-Halle in dein Profil ein – andere sehen dich dann hier.")
                } else {
                    ForEach(Array(ranking.enumerated()), id: \.element.id) { index, member in
                        HStack(spacing: 12) {
                            Text("\(index + 1).")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(index < 3 ? Color.primary : .secondary)
                                .frame(width: 28, alignment: .trailing)
                            NavigationLink(value: member.profileID) {
                                HStack(spacing: 12) {
                                    ProfilePhoto(name: member.displayName, url: account.imageURL(member.avatarPath, bucket: .avatars), size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName).font(.body.weight(member.profileID == account.userID ? .bold : .semibold))
                                        Text("\(member.ratedMatches) Matches").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(member.rating.rounded()))").font(Theme.scoreFont(size: 17))
                                Text("Level \(member.level.formatted(.number.precision(.fractionLength(1))))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(member.profileID == account.userID ? Theme.surface : .clear)
                        .revealOnAppear(delay: min(Double(index) * 0.04, 0.3))
                        if index < ranking.count - 1 { RowDivider(inset: 100) }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(club)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .profileNavigation()
    }

    private var header: some View {
        HStack(spacing: 0) {
            stat("\(ranking.count)", "Spieler")
            stat("\(activity?.players ?? 0)", "aktiv (30 Tage)")
            stat("\(activity?.matches30d ?? 0)", "Matches (30 Tage)")
        }
        .padding(.vertical, 16)
        .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        async let r = account.clubRanking(club)
        async let a = account.clubActivity(club)
        async let g = account.openGames(club: club)
        ranking = await r
        activity = await a
        games = await g
        isLoading = false
    }
}
