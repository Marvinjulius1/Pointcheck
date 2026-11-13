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

    enum ProfileTab: String, CaseIterable, Identifiable {
        case results = "Ergebnisse", posts = "Beiträge", badges = "Erfolge"
        var id: Self { self }
    }

    private var isMe: Bool { profileID == account.userID }

    var body: some View {
        ScrollView {
            if let page {
                VStack(spacing: 20) {
                    header(page)
                    if page.isVisible {
                        statsStrip(page)
                        Picker("Bereich", selection: $tab) {
                            ForEach(isMe ? ProfileTab.allCases : [.results, .posts]) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        content
                    } else {
                        privateNotice(page)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            } else if isLoading {
                ProgressView().padding(.top, 80)
            } else {
                EmptyState(symbol: "person.slash", title: "Profil nicht gefunden",
                           message: "Dieses Profil gibt es nicht mehr oder es ist gerade nicht erreichbar.")
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(page?.username.map { "@\($0)" } ?? "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Beitrag schreiben", systemImage: "square.and.pencil") { showsComposer = true }
                        Button("Profil bearbeiten", systemImage: "person.crop.circle") { showsEditor = true }
                        NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    ProfilePhoto(name: page.displayName, url: account.imageURL(page.avatarPath, bucket: .avatars), size: 86)
                    if let level = page.level {
                        Text(level.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.me.gradient, in: .capsule)
                            .overlay(Capsule().stroke(Color(.systemGroupedBackground), lineWidth: 2))
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
                    secondaryButton("Beitrag", symbol: "plus") { showsComposer = true }
                }
            } else {
                HStack(spacing: 10) {
                    FollowButton(profileID: page.id, relation: $relation)
                        .frame(maxWidth: .infinity)
                    if page.isVisible {
                        ShareLink(item: "Spiel mit mir Padel! Folge @\(page.username ?? page.displayName) in Pointcheck.") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 34)
                                .background(Color(.tertiarySystemFill), in: .capsule)
                        }
                        .buttonStyle(.plain)
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
            Text(value.formatted())
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: Stats strip

    private func statsStrip(_ page: ProfilePage) -> some View {
        Card {
            HStack(spacing: 0) {
                stat(value: page.rating.map { Int($0.rounded()).formatted() } ?? "–", label: "Punkte")
                Divider().frame(height: 36)
                stat(value: page.winRate?.percentText ?? "–", label: "Siegquote")
                Divider().frame(height: 36)
                stat(value: streakText(page.currentStreak), label: "Serie",
                     tint: (page.currentStreak ?? 0) > 0 ? Theme.me : (page.currentStreak ?? 0) < 0 ? Theme.opponent : .primary)
                Divider().frame(height: 36)
                stat(value: "\(page.ratedMatches ?? 0)", label: "Matches")
            }
            .padding(.vertical, 14)
        }
    }

    private func stat(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(value)
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
                LazyVStack(spacing: 10) {
                    ForEach(results) { ResultCard(result: $0) }
                }
            }
        case .posts:
            if posts.isEmpty {
                EmptyState(symbol: "square.and.pencil", title: "Noch keine Beiträge",
                           message: isMe ? "Teile ein Ergebnis oder ein Foto vom Platz." : "Hier erscheinen Beiträge.",
                           actionTitle: isMe ? "Beitrag schreiben" : nil,
                           action: isMe ? { showsComposer = true } : nil)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        PostCard(
                            authorName: page?.displayName ?? "",
                            authorAvatar: account.imageURL(page?.avatarPath, bucket: .avatars),
                            text: post.text, imageURL: account.imageURL(post.imagePath, bucket: .posts),
                            match: post.match, createdAt: post.createdAt,
                            canDelete: isMe,
                            onDelete: { Task { try? await account.deletePost(post.id); await load() } }
                        )
                    }
                }
            }
        case .badges:
            BadgesGrid()
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

// MARK: - Result card

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
                    if canDelete {
                        Menu {
                            Button("Beitrag löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(6)
                        }
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
        .background(Color(.systemGroupedBackground))
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
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.me.gradient, in: .circle)
                                    .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2))
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
