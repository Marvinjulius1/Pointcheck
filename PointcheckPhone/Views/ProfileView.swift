import PadelStats
import PhotosUI
import SwiftUI

/// Instagram-style profile: photo, counters, level, tabs with results, posts and badges.
/// Used for my own profile (profile tab) and for everyone else (via navigation).
struct ProfileView: View {
    let profileID: UUID
    @Environment(AccountService.self) private var account
    @State private var page: ProfilePage?
    @State private var relation: FollowRelation = .none
    @State private var results: [ProfileResult] = []
    @State private var posts: [ProfilePost] = []
    @State private var tab: ProfileTab = .results
    @State private var isLoading = true
    @State private var showsEditor = false
    @State private var showsComposer = false
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(BadgeTracker.self) private var badges

    enum ProfileTab: String, CaseIterable, Identifiable {
        case results = "Ergebnisse", posts = "Beiträge", badges = "Erfolge"
        var id: Self { self }

        var symbol: String {
            switch self {
            case .results: "square.grid.3x3"
            case .posts: "text.below.photo"
            case .badges: "trophy"
            }
        }
    }

    /// Instagram-style icon tabs with a sliding underline.
    private var tabBar: some View {
        let tabs: [ProfileTab] = isMe ? ProfileTab.allCases : [.results, .posts]
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs) { value in
                    Button {
                        withAnimation(.snappy) { tab = value }
                        if value == .badges { badges.markSeen() }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: value.symbol)
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(tab == value ? .primary : .secondary)
                                .overlay(alignment: .topTrailing) {
                                    if value == .badges, badges.hasUnseen {
                                        Circle().fill(Theme.me).frame(width: 7, height: 7).offset(x: 4, y: -3)
                                    }
                                }
                            Rectangle()
                                .fill(tab == value ? Color.primary : .clear)
                                .frame(height: 1.5)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(value.rawValue)
                    .accessibilityAddTraits(tab == value ? .isSelected : [])
                }
            }
            FeedDivider()
        }
        .sensoryFeedback(.selection, trigger: tab)
    }

    private var isMe: Bool { profileID == account.userID }

    var body: some View {
        ScrollView {
            if let page {
                VStack(spacing: 24) {
                    header(page)
                        .padding(.horizontal, 20)
                        .revealOnAppear()
                    if page.isVisible {
                        statsStrip(page)
                            .padding(.horizontal, 20)
                            .revealOnAppear(delay: 0.06)
                        tabBar
                            .padding(.top, 4)
                        content
                            .revealOnAppear(delay: 0.12)
                    } else {
                        privateNotice(page)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 32)
            } else if isLoading {
                VStack(spacing: 20) {
                    HStack(spacing: 24) {
                        SkeletonBlock(height: 86, width: 86, radius: 43)
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in
                                VStack(spacing: 6) {
                                    SkeletonBlock(height: 18, width: 36)
                                    SkeletonBlock(height: 10, width: 48)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    SkeletonBlock(height: 14, width: 160).frame(maxWidth: .infinity, alignment: .leading)
                    SkeletonBlock(height: 12, width: 240).frame(maxWidth: .infinity, alignment: .leading)
                    SkeletonBlock(height: 40, radius: 20)
                    SkeletonBlock(height: 72, radius: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                EmptyState(symbol: "person.slash", title: "Profil nicht gefunden",
                           message: "Dieses Profil gibt es nicht mehr oder es ist gerade nicht erreichbar.")
            }
        }
        .background(Theme.background)
        .navigationTitle(page?.username.map { "@\($0)" } ?? "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ActivityView() } label: {
                        Image(systemName: "bell")
                            .foregroundStyle(Color.primary)
                            .overlay(alignment: .topTrailing) {
                                if account.activityCount > 0 {
                                    Circle()
                                        .fill(Theme.me)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 2, y: -1)
                                }
                            }
                    }
                    .accessibilityLabel(account.activityCount > 0 ? "Aktivität, \(account.activityCount) neu" : "Aktivität")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
        }
        .task(id: profileID) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsEditor, onDismiss: { Task { await load() } }) {
            if let profile = account.profile { ProfileEditor(profile: profile) }
        }
        .sheet(isPresented: $showsComposer, onDismiss: { Task { await load() } }) {
            PostComposer(match: nil)
        }
    }

    // MARK: Header

    private func header(_ page: ProfilePage) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                ZStack(alignment: .bottomTrailing) {
                    ProfilePhoto(name: page.displayName, url: account.imageURL(page.avatarPath, bucket: .avatars), size: 86)
                    if let level = page.level {
                        Text(level.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.accent, in: .capsule)
                            .overlay(Capsule().stroke(Theme.background, lineWidth: 2))
                            .offset(x: 4, y: 4)
                            .accessibilityLabel("Level \(level.formatted(.number.precision(.fractionLength(1))))")
                    }
                }
                HStack(spacing: 0) {
                    counter(page.posts, "Beiträge", kind: nil)
                    counter(page.followers, "Follower", kind: page.isVisible ? .followers : nil)
                    counter(page.following, "Folge ich", kind: page.isVisible ? .following : nil)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(page.displayName).font(.headline)
                    if page.visibility == .followers {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Privates Profil")
                    }
                }
                if let club = page.homeClub, !club.isEmpty {
                    Label(club, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let bio = page.bio, !bio.isEmpty {
                    Text(bio).font(.subheadline)
                }
                if page.followsMe, !isMe {
                    Text("Folgt dir")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isMe {
                HStack(spacing: 10) {
                    secondaryButton("Profil bearbeiten", symbol: "pencil") { showsEditor = true }
                    profileShareButton(page)
                }
            } else {
                HStack(spacing: 10) {
                    FollowButton(profileID: page.id, relation: $relation)
                        .frame(maxWidth: .infinity)
                    if page.isVisible {
                        profileShareButton(page)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func counter(_ value: Int, _ label: String, kind: PeopleListRoute.Kind?) -> some View {
        Group {
            if let kind {
                NavigationLink(value: PeopleListRoute(kind: kind, profileID: profileID)) { counterLabel(value, label) }
                    .buttonStyle(.plain)
            } else {
                counterLabel(value, label)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func counterLabel(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            CountUpText(value: Double(value))
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func profileShareButton(_ page: ProfilePage) -> some View {
        ShareCardButton(title: "Mein Pointcheck-Profil") {
            let photo = await ShareRenderer.load(account.imageURL(page.avatarPath, bucket: .avatars))
            return ProfileShareCard(page: page, photo: photo)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 48, height: 38)
                .background(Color(.tertiarySystemFill), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil teilen")
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: .capsule)
        }
        .buttonStyle(.pressScale)
    }

    // MARK: Stats strip

    private func statsStrip(_ page: ProfilePage) -> some View {
        HStack(spacing: 0) {
            stat(number: page.rating, text: nil, label: "Punkte", delay: 0)
            stat(number: (page.winRate ?? 0) * 100, text: page.winRate == nil ? "–" : nil, label: "Siegquote", delay: 0.08, suffix: " %")
            stat(number: nil, text: streakText(page.currentStreak), label: "Serie",
                 tint: (page.currentStreak ?? 0) > 0 ? Theme.me : (page.currentStreak ?? 0) < 0 ? Theme.opponent : .primary)
            stat(number: Double(page.ratedMatches ?? 0), text: nil, label: "Matches", delay: 0.24)
        }
        .padding(.vertical, 18)
        .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func stat(number: Double?, text: String?, label: String, tint: Color = .primary, delay: Double = 0, suffix: String = "") -> some View {
        VStack(spacing: 3) {
            Group {
                if let text {
                    Text(text)
                } else if let number {
                    CountUpText(value: number, delay: delay) { Int($0.rounded()).formatted() + suffix }
                } else {
                    Text(text ?? "–")
                }
            }
            .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func streakText(_ streak: Int?) -> String {
        guard let streak, streak != 0 else { return "–" }
        return streak > 0 ? "\(streak) S" : "\(-streak) N"
    }

    // MARK: Tabs

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .results:
            if results.isEmpty {
                EmptyState(symbol: "figure.tennis", title: "Noch keine Ergebnisse",
                           message: isMe ? "Bestätigte Matches erscheinen hier. Trag deine Gegner ein und lass sie bestätigen."
                                         : "Sobald \(page?.displayName ?? "") bestätigte Matches hat, stehen sie hier.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(results) { result in
                        NavigationLink {
                            ResultDetailView(result: result)
                                .zoomDestination(result.matchID, in: zoomNamespace)
                        } label: {
                            ResultTile(result: result)
                                .zoomSource(result.matchID, in: zoomNamespace)
                        }
                        .buttonStyle(.pressScale)
                    }
                }
                .padding(.horizontal, 2)
            }
        case .posts:
            if posts.isEmpty {
                EmptyState(symbol: "square.and.pencil", title: "Noch keine Beiträge",
                           message: isMe ? "Teile ein Ergebnis oder ein Foto vom Platz." : "Hier erscheinen Beiträge.",
                           actionTitle: isMe ? "Beitrag schreiben" : nil,
                           action: isMe ? { showsComposer = true } : nil)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(posts) { post in
                        NavigationLink {
                            PostDetailView(post: post, authorName: page?.displayName ?? "",
                                           authorAvatar: account.imageURL(page?.avatarPath, bucket: .avatars),
                                           canDelete: isMe, onDelete: { Task { try? await account.deletePost(post.id); await load() } })
                                .zoomDestination(post.id, in: zoomNamespace)
                        } label: {
                            PostTile(post: post, imageURL: account.imageURL(post.imagePath, bucket: .posts))
                                .zoomSource(post.id, in: zoomNamespace)
                        }
                        .buttonStyle(.pressScale)
                    }
                }
                .padding(.horizontal, 2)
            }
        case .badges:
            BadgesGrid().padding(.horizontal)
        }
    }

    private func privateNotice(_ page: ProfilePage) -> some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(.secondary)
                Text("Dieses Profil ist privat")
                    .font(.headline)
                Text(relation == .pending
                     ? "Deine Anfrage wartet auf Bestätigung."
                     : "Folge \(page.displayName), um Ergebnisse und Beiträge zu sehen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    // MARK: Loading

    private func load() async {
        if profileID == DemoProfile.id {
            page = DemoProfile.page
            relation = .none
            results = DemoProfile.results
            posts = DemoProfile.posts
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            page = try await account.profilePage(profileID)
        } catch {
            page = nil
        }
        guard let page else { return }
        relation = page.relation
        guard page.isVisible else { return }
        async let loadedResults = account.profileResults(profileID)
        async let loadedPosts = account.profilePosts(profileID)
        results = await loadedResults
        posts = await loadedPosts
    }
}

// MARK: - Grid tiles

/// Square tile in the results grid: sets score big, result text small.
struct ResultTile: View {
    let result: ProfileResult

    private var tint: Color { result.playerWon ? Theme.me : Theme.opponent }
    private var sets: TeamScore {
        result.setsFromPlayer.reduce(into: TeamScore.zero) { acc, set in
            if let winner = set.winner { acc[winner] += 1 }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("\(sets.me):\(sets.opponent)")
                .font(Theme.scoreFont(size: 30))
                .foregroundStyle(tint)
            Text(result.resultText)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(result.startedAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(tint.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.playerWon ? "Sieg" : "Niederlage") \(result.resultText)")
    }
}

/// Square tile in the posts grid: image, or result, or text.
struct PostTile: View {
    let post: ProfilePost
    var imageURL: URL?

    var body: some View {
        ZStack {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surface }
                }
            } else if let match = post.match {
                let tint = match.authorWon ? Theme.me : Theme.opponent
                tint.opacity(0.12)
                VStack(spacing: 4) {
                    Text("\(match.setsWon.me):\(match.setsWon.opponent)")
                        .font(Theme.scoreFont(size: 28))
                        .foregroundStyle(tint)
                    Text(match.resultText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 6)
                }
            } else {
                Theme.surface
                Text(post.text)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

/// Full post when a tile is tapped.
struct PostDetailView: View {
    let post: ProfilePost
    let authorName: String
    var authorAvatar: URL?
    var canDelete = false
    var onDelete: (() -> Void)?
    @Environment(AccountService.self) private var account

    var body: some View {
        ScrollView {
            PostCard(authorName: authorName, authorAvatar: authorAvatar, text: post.text,
                     imageURL: account.imageURL(post.imagePath, bucket: .posts), match: post.match,
                     createdAt: post.createdAt, canDelete: canDelete, onDelete: onDelete)
                .padding()
        }
        .background(Theme.background)
        .navigationTitle("Beitrag")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single confirmed result, opened from the profile grid.
struct ResultDetailView: View {
    let result: ProfileResult

    private var attached: AttachedMatch? {
        AttachedMatch(matchID: result.matchID, startedAt: result.startedAt, sets: result.sets,
                      winnerSide: result.winnerSide, authorSide: result.playerSide,
                      partnerName: result.partnerName, opponentNames: result.opponentNames)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let attached {
                    ResultBanner(match: attached)
                }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(result.setsFromPlayer.enumerated()), id: \.offset) { index, set in
                            if index > 0 { RowDivider(inset: 16) }
                            HStack {
                                Text(set.isSuperTiebreak ? "Match-Tiebreak" : "Satz \(index + 1)")
                                Spacer()
                                Text(set.resultText)
                                    .font(Theme.scoreFont(size: 17))
                                    .foregroundStyle(set.winner == .me ? Theme.me : set.winner == .opponent ? Theme.opponent : .primary)
                            }
                            .padding(16)
                        }
                        RowDivider(inset: 16)
                        HStack {
                            Text("Gespielt")
                            Spacer()
                            Text(result.startedAt.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                        }
                        .padding(16)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Ergebnis")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Result card (lists)

struct ResultCard: View {
    let result: ProfileResult

    var body: some View {
        Card {
            HStack(spacing: 12) {
                ResultIcon(result: result.playerWon ? .won : .lost)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.opponentNames.map { "vs. \($0)" } ?? "Match")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(result.startedAt.formatted(.dateTime.day().month(.abbreviated)))
                        if let partner = result.partnerName {
                            Text("· mit \(partner)")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(result.resultText)
                    .font(Theme.scoreFont(size: 16))
                    .foregroundStyle(result.playerWon ? Theme.me : Theme.opponent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Post card

/// A post in the feed or on a profile.
struct PostCard: View {
    let authorName: String
    var authorAvatar: URL?
    var authorID: UUID?
    let text: String
    var imageURL: URL?
    var match: AttachedMatch?
    let createdAt: Date
    var canDelete = false
    var onDelete: (() -> Void)?
    @State private var confirmDelete = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Group {
                        if let authorID {
                            NavigationLink(value: authorID) { authorLine }.buttonStyle(.plain)
                        } else {
                            authorLine
                        }
                    }
                    Spacer()
                    Menu {
                        ShareCardButton(title: "Beitrag aus Pointcheck") {
                            async let author = ShareRenderer.load(authorAvatar)
                            async let picture = ShareRenderer.load(imageURL)
                            return await PostShareCard(authorName: authorName, authorPhoto: author, text: text,
                                                       photo: picture, match: match, date: createdAt)
                        } label: {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        if canDelete {
                            Button("Beitrag löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(6)
                    }
                }

                if !text.isEmpty {
                    Text(text).font(.body)
                }

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color(.tertiarySystemFill)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fill)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                }

                if let match {
                    MatchChip(match: match)
                }
            }
            .padding(16)
        }
        .confirmationDialog("Beitrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { onDelete?() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var authorLine: some View {
        HStack(spacing: 10) {
            ProfilePhoto(name: authorName, url: authorAvatar, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(authorName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(createdAt.relativeShort).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Compact result block inside a post or feed item.
struct MatchChip: View {
    let match: AttachedMatch

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(match.authorWon ? "Sieg" : "Niederlage")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(match.authorWon ? Theme.me : Theme.opponent)
                ResultLine(text: match.resultText, won: match.authorWon, size: 20)
                Text([match.partnerName.map { "mit \($0)" }, match.opponentNames.map { "gegen \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(match.setsWon.me):\(match.setsWon.opponent)")
                .font(Theme.scoreFont(size: 26))
                .foregroundStyle(match.authorWon ? Theme.me : Theme.opponent)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Follower / following lists

struct PeopleListView: View {
    let route: PeopleListRoute
    private var kind: PeopleListRoute.Kind { route.kind }
    private var profileID: UUID { route.profileID }
    @Environment(AccountService.self) private var account
    @State private var people: [PersonRow] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if loaded && people.isEmpty {
                EmptyState(symbol: "person.2", title: kind == .followers ? "Noch keine Follower" : "Folgt niemandem",
                           message: kind == .followers ? "Teile dein Profil, damit dir Mitspieler folgen." : "Finde Spieler über die Suche.")
            } else {
                Card {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { RowDivider(inset: 72) }
                        PersonListRow(person: person)
                    }
                }
                .padding()
            }
        }
        .background(Theme.background)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            people = kind == .followers ? await account.followers(of: profileID) : await account.following(of: profileID)
            loaded = true
        }
    }
}

// MARK: - Editor

struct ProfileEditor: View {
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var homeClub: String
    @State private var visibility: ProfileVisibility
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPreview: Image?
    @State private var photoData: Data?
    @State private var errorText: String?
    @State private var isSaving = false
    private let avatarPath: String?
    private let name: String

    init(profile: RemoteProfile) {
        _displayName = State(initialValue: profile.displayName)
        _username = State(initialValue: profile.username ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _homeClub = State(initialValue: profile.homeClub ?? "")
        _visibility = State(initialValue: profile.visibility)
        avatarPath = profile.avatarPath
        name = profile.displayName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                if let photoPreview {
                                    photoPreview.resizable().scaledToFill()
                                        .frame(width: 96, height: 96).clipShape(.circle)
                                } else {
                                    ProfilePhoto(name: name, url: account.imageURL(avatarPath, bucket: .avatars), size: 96)
                                }
                                Image(systemName: "camera.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.onAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.accent, in: .circle)
                                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Anzeigename", text: $displayName)
                }
                Section {
                    TextField("benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Benutzername")
                } footer: {
                    Text("Andere finden dich als @\(username.isEmpty ? "benutzername" : username.lowercased()).")
                }
                Section {
                    TextField("Kurz über dich (max. 160 Zeichen)", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Heimat-Halle oder Stadt", text: $homeClub)
                } header: {
                    Text("Über dich")
                }
                Section {
                    Picker("Sichtbarkeit", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Wer darf dein Profil sehen?")
                } footer: {
                    Text(visibility.explanation)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.opponent) }
                }
            }
            .navigationTitle("Profil bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let jpeg = image.resizedJPEG(maxSide: 600, quality: 0.85)
        photoData = jpeg
        if let jpeg, let preview = UIImage(data: jpeg) { photoPreview = Image(uiImage: preview) }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            if let photoData { try await account.uploadAvatar(photoData) }
            try await account.updateProfile(displayName: displayName, username: username,
                                            visibility: visibility, bio: bio, homeClub: homeClub)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension UIImage {
    /// Scales down so the longer side is at most `maxSide` and encodes as JPEG.
    func resizedJPEG(maxSide: CGFloat, quality: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target, format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        let image = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return image.jpegData(compressionQuality: quality)
    }
}
