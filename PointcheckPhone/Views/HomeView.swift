import Charts
import PadelStats
import SwiftData
import SwiftUI

/// Start tab, Instagram-style: avatar row, then the feed edge to edge.
/// On top a compact Trade-Republic-style strip with the playing strength.
struct HomeView: View {
    @Query(sort: \StoredMatch.startDate, order: .reverse) private var stored: [StoredMatch]
    @Environment(WatchSync.self) private var sync
    @Environment(AccountService.self) private var account
    @State private var showsComposer = false
    @State private var following: [PersonRow] = []
    @Environment(\.zoomNamespace) private var zoomNamespace

    private var matches: [MatchSummary] { account.allMatches(local: stored.map(\.summary)) }

    var body: some View {
        let all = matches
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                RatingStrip(matches: all)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .revealOnAppear()

                avatarRow
                    .revealOnAppear(delay: 0.08)

                FeedDivider()
                    .padding(.top, 4)

                feed
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Pointcheck")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { Image(systemName: "plus.app") }
                    .accessibilityLabel("Beitrag schreiben")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .tennisBallRefresh {
            sync.requestAll()
            await account.refresh()
            await loadFollowing()
        }
        .task { await loadFollowing() }
        .sheet(isPresented: $showsComposer) { PostComposer(match: nil) }
        .profileNavigation()
    }

    private func loadFollowing() async {
        guard let id = account.userID else { return }
        following = await account.following(of: id)
        if account.suggestions.isEmpty { await account.loadSuggestions() }
    }

    // MARK: Avatar row

    private var avatarRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                if let me = account.profile {
                    NavigationLink(value: me.id) {
                        AvatarBubble(name: me.displayName, url: account.imageURL(me.avatarPath, bucket: .avatars),
                                     caption: "Du")
                    }
                    .buttonStyle(.pressScale)
                }
                ForEach(following) { person in
                    NavigationLink(value: person.profileID) {
                        AvatarBubble(name: person.displayName, url: account.imageURL(person.avatarPath, bucket: .avatars))
                            .zoomSource(person.profileID, in: zoomNamespace)
                    }
                    .buttonStyle(.pressScale)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                ForEach(Array(account.suggestions.prefix(8).enumerated()), id: \.element.id) { index, person in
                    NavigationLink(value: person.profileID) {
                        AvatarBubble(name: person.displayName, url: account.imageURL(person.avatarPath, bucket: .avatars))
                            .zoomSource(person.profileID, in: zoomNamespace)
                            .overlay(alignment: .topTrailing) {
                                PulsingPlus(delay: Double(index) * 0.1)
                                    .offset(x: -4, y: 2)
                            }
                    }
                    .buttonStyle(.pressScale)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if following.isEmpty {
                    NavigationLink(value: DemoProfile.id) {
                        AvatarBubble(name: DemoProfile.name, url: account.imageURL(DemoProfile.avatarPath, bucket: .avatars),
                                     caption: "Demo", highlighted: DemoProfile.isFollowed)
                            .zoomSource(DemoProfile.id, in: zoomNamespace)
                    }
                    .buttonStyle(.pressScale)
                }
                NavigationLink { SearchView() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, height: 64)
                            .background(Theme.surface, in: .circle)
                            .padding(3)
                        Text("Suchen").font(.caption).frame(width: 72)
                    }
                }
                .buttonStyle(.pressScale)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: account.suggestions)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: following)
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feed: some View {
        if account.feed.isEmpty, account.isLoadingFeed {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRow(showsImage: true)
                FeedDivider()
            }
        } else if account.feed.isEmpty {
            EmptyState(symbol: "sparkles", title: "Noch nichts im Feed",
                       message: "Folge Spielern oben in der Reihe – oder teile dein erstes Match.",
                       actionTitle: "Beitrag schreiben", action: { showsComposer = true })
                .padding(.top, 8)
            SectionTitle("So sieht ein Beitrag aus").padding(.horizontal, 16)
            FeedEntry(item: DemoProfile.feedItem)
            FeedDivider()
        } else {
            ForEach(Array(account.feed.enumerated()), id: \.element.id) { index, item in
                FeedEntry(item: item)
                    .revealOnAppear(delay: min(Double(index) * 0.05, 0.3))
                    .onAppear {
                        if item.id == account.feed.last?.id {
                            Task { await account.loadMoreFeed() }
                        }
                    }
                FeedDivider()
            }
            if account.feedHasMore {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }
}

// MARK: - Rating strip (compact hero)

/// Compact version of the rating hero: value counts up, sparkline draws itself.
private struct RatingStrip: View {
    let matches: [MatchSummary]
    @Environment(AccountService.self) private var account

    private var source: (points: [RatingPoint], current: Double, isServer: Bool) {
        if let profile = account.profile, let first = account.ratingHistory.first {
            let start = RatingPoint(date: first.createdAt.addingTimeInterval(-1), rating: first.ratingBefore)
            let points = [start] + account.ratingHistory.map { RatingPoint(date: $0.createdAt, rating: $0.ratingAfter) }
            return (points, profile.rating, true)
        }
        let report = PadelStats.localRatings(matches)
        return (report.history.map { RatingPoint(date: $0.date, rating: $0.rating) }, report.me.rating, false)
    }

    var body: some View {
        let data = source
        let now = Date.now
        let window = RatingSeries.window(data.points, current: data.current,
                                         since: now.addingTimeInterval(-30 * 86_400), now: now)
        let change = RatingSeries.change(window)
        let isUp = change.delta >= 0
        let color = isUp ? Theme.me : Theme.opponent

        NavigationLink {
            StatsView()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spielstärke")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    CountUpText(value: data.current)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .overlay(alignment: .trailing) {
                            if account.pendingRatingDelta != 0 {
                                FloatingDelta(delta: account.pendingRatingDelta) { account.acknowledgeRatingDelta() }
                                    .offset(x: 56)
                            }
                        }
                    ChangeLabel(change: change.delta, base: change.base, suffix: "30 Tage")
                }
                Spacer()
                Chart(window) { point in
                    LineMark(x: .value("Datum", point.date), y: .value("Punkte", point.rating))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    AreaMark(x: .value("Datum", point.date), y: .value("Punkte", point.rating))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: yDomain(window))
                .frame(width: 120, height: 56)
                .drawOnAppear()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressScale)
    }

    private func yDomain(_ window: [RatingPoint]) -> ClosedRange<Double> {
        let values = window.map(\.rating)
        let low = values.min() ?? 1500, high = values.max() ?? 1500
        let pad = max((high - low) * 0.25, 10)
        return (low - pad)...(high + pad)
    }
}

// MARK: - Feed entry (edge to edge, Instagram-style)

private struct FeedEntry: View {
    let item: FeedItem
    @Environment(AccountService.self) private var account
    @State private var confirmDelete = false

    private var isMine: Bool { item.authorID == account.userID }
    @Environment(\.zoomNamespace) private var zoomNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                NavigationLink(value: item.authorID) {
                    HStack(spacing: 12) {
                        ProfilePhoto(name: item.authorName, url: account.imageURL(item.authorAvatar, bucket: .avatars), size: 40)
                            .zoomSource(item.authorID, in: zoomNamespace)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.authorName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    ShareCardButton(title: "Beitrag aus Pointcheck") {
                        async let author = ShareRenderer.load(account.imageURL(item.authorAvatar, bucket: .avatars))
                        async let picture = ShareRenderer.load(account.imageURL(item.imagePath, bucket: .posts))
                        return await PostShareCard(authorName: item.authorName, authorPhoto: author, text: item.text ?? "",
                                                   photo: picture, match: item.match, date: item.createdAt)
                    } label: {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                    if isMine, item.kind == .post {
                        Button("Beitrag löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(8)
                }
            }
            .padding(.horizontal, 16)

            if let text = item.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
            }

            if let url = account.imageURL(item.imagePath, bucket: .posts) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Theme.surface
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fill)
                .clipped()
            }

            if let match = item.match {
                ResultBanner(match: match)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 18)
        .confirmationDialog("Beitrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { try? await account.deletePost(item.id) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var subtitle: String {
        switch item.kind {
        case .post: item.createdAt.relativeShort
        case .match: "hat \(item.match?.authorWon == true ? "gewonnen" : "gespielt") · \(item.createdAt.relativeShort)"
        }
    }
}

/// Result as a wide, tinted banner – the "image" of a match post.
struct ResultBanner: View {
    let match: AttachedMatch
    @State private var popped = false

    private var tint: Color { match.authorWon ? Theme.me : Theme.opponent }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(match.authorWon ? "SIEG" : "NIEDERLAGE")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(tint)
                Text(match.resultText)
                    .font(Theme.scoreFont(size: 26))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text([match.partnerName.map { "mit \($0)" }, match.opponentNames.map { "gegen \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(match.setsWon.me):\(match.setsWon.opponent)")
                .font(Theme.scoreFont(size: 40))
                .foregroundStyle(tint)
                .scaleEffect(popped ? 1 : 0.6)
                .opacity(popped ? 1 : 0)
        }
        .padding(18)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.1)) { popped = true }
        }
        .background(
            LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small motion pieces

/// "+24" that rises and fades (green), or sinks (red) for a loss of points.
struct FloatingDelta: View {
    let delta: Double
    let onDone: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUp: Bool { delta > 0 }

    var body: some View {
        Text((isUp ? "+" : "−") + Int(abs(delta).rounded()).formatted())
            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(isUp ? Theme.me : Theme.opponent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((isUp ? Theme.me : Theme.opponent).opacity(0.14), in: .capsule)
            .offset(y: shown && !reduceMotion ? (isUp ? -34 : 34) : 0)
            .opacity(shown ? 0 : 1)
            .task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeOut(duration: 1.6)) { shown = true }
                try? await Task.sleep(for: .seconds(1.7))
                onDone()
            }
            .accessibilityLabel("Spielstärke \(isUp ? "plus" : "minus") \(Int(abs(delta).rounded()))")
    }
}

/// Green plus badge that pulses once when it appears.
struct PulsingPlus: View {
    var delay: Double = 0
    @State private var pulsed = false

    var body: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(.white, Theme.me)
            .scaleEffect(pulsed ? 1 : 0.6)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.5).delay(delay)) { pulsed = true }
            }
            .accessibilityHidden(true)
    }
}
