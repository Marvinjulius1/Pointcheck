import PadelStats
import SwiftData
import SwiftUI

/// Start tab: playing strength like a portfolio value, then the feed of people I follow.
struct HomeView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync
    @Environment(AccountService.self) private var account
    @State private var showsComposer = false

    private var matches: [MatchSummary] { account.allMatches(local: stored.map(\.summary)) }

    var body: some View {
        let all = matches
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RatingHero(matches: all)
                    .padding(.bottom, 4)

                statsLink(all)

                SectionTitle("Feed") {
                    Button("Beitrag", systemImage: "square.and.pencil") { showsComposer = true }
                }
                feed
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pointcheck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Suche")
            }
        }
        .refreshable {
            sync.requestAll()
            await account.refresh()
        }
        .sheet(isPresented: $showsComposer) { PostComposer(match: nil) }
        .profileNavigation()
    }

    private func statsLink(_ all: [MatchSummary]) -> some View {
        let overview = PadelStats.overview(all)
        return Card {
            NavigationLink { StatsView() } label: {
                HStack(spacing: 0) {
                    miniStat(overview.winRate?.percentText ?? "–", "Siegquote")
                    miniStat("\(overview.matchesPlayed)", "Matches")
                    miniStat(streakText(overview.currentStreak), "Serie",
                             tint: overview.currentStreak > 0 ? Theme.me : overview.currentStreak < 0 ? Theme.opponent : .primary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 16)
                }
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func miniStat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func streakText(_ streak: Int) -> String {
        switch streak {
        case 0: "–"
        case 1...: "\(streak) S"
        default: "\(-streak) N"
        }
    }

    @ViewBuilder
    private var feed: some View {
        if account.feed.isEmpty {
            EmptyState(symbol: "sparkles", title: "Dein Feed ist noch leer",
                       message: "Folge Spielern, dann erscheinen ihre Ergebnisse und Beiträge hier.")
            if !account.suggestions.isEmpty {
                SectionTitle("Vorschläge")
                Card {
                    ForEach(Array(account.suggestions.prefix(5).enumerated()), id: \.element.id) { index, person in
                        if index > 0 { RowDivider(inset: 72) }
                        PersonListRow(person: person, subtitle: person.reason)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(account.feed) { item in
                    FeedCard(item: item)
                        .onAppear {
                            if item.id == account.feed.last?.id {
                                Task { await account.loadMoreFeed() }
                            }
                        }
                }
                if account.feedHasMore {
                    ProgressView().padding()
                }
            }
        }
    }
}

/// One feed entry: a post card, or a confirmed match of someone I follow.
private struct FeedCard: View {
    let item: FeedItem
    @Environment(AccountService.self) private var account

    var body: some View {
        switch item.kind {
        case .post:
            PostCard(
                authorName: item.authorName,
                authorAvatar: account.imageURL(item.authorAvatar, bucket: .avatars),
                authorID: item.authorID,
                text: item.text ?? "",
                imageURL: account.imageURL(item.imagePath, bucket: .posts),
                match: item.match,
                createdAt: item.createdAt,
                canDelete: item.authorID == account.userID,
                onDelete: { Task { try? await account.deletePost(item.id) } }
            )
        case .match:
            if let match = item.match {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink(value: item.authorID) {
                            HStack(spacing: 10) {
                                ProfilePhoto(name: item.authorName, url: account.imageURL(item.authorAvatar, bucket: .avatars), size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.authorName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text("hat \(match.authorWon ? "gewonnen" : "verloren") · \(item.createdAt.relativeShort)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        MatchChip(match: match)
                    }
                    .padding(16)
                }
            }
        }
    }
}
