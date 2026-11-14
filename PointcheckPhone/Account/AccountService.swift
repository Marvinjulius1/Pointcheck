import Foundation
import Observation
import PadelStats
import Supabase

/// Account, profile and everything that talks to the Supabase backend.
@Observable
@MainActor
final class AccountService {
    enum State: Equatable {
        case loading
        case signedOut
        /// Arrived through a password-reset link: a new password must be set.
        case resettingPassword
        case signedIn
    }

    private(set) var state: State = .loading
    private(set) var profile: RemoteProfile?
    private(set) var openConfirmations: [OpenConfirmation] = []
    /// Status of my uploaded matches, by match id.
    private(set) var uploads: [UUID: RemoteMatchStatus] = [:]
    private(set) var ratingHistory: [RatingHistoryRow] = []
    private(set) var followRequests: [PersonRow] = []
    private(set) var recentFollowers: [PersonRow] = []
    private(set) var feed: [FeedItem] = []
    private(set) var feedHasMore = false
    private(set) var isLoadingFeed = false
    /// Rating change since the person last saw their rating (shown once as a floating label).
    private(set) var pendingRatingDelta: Double = 0
    private static let lastSeenRatingKey = "rating.lastSeen"
    private(set) var suggestions: [PersonRow] = []
    /// Players opened from the search, newest first (kept on this device).
    private(set) var recentSearches: [PersonRow] = AccountService.loadRecentSearches()
    private static let recentSearchesKey = "search.recent"
    /// Confirmed matches someone else entered with me in it (not on my watch).
    private(set) var foreignMatches: [MatchSummary] = []
    /// Matches I play in but did not enter, by id (for the "entered by a co-player" label).
    private(set) var foreignIDs: Set<UUID> = []

    /// Upload new watch matches automatically after signing in (setting in the Konto tab).
    var autoUpload: Bool {
        get { access(keyPath: \.autoUpload); return UserDefaults.standard.object(forKey: Self.autoUploadKey) as? Bool ?? true }
        set { withMutation(keyPath: \.autoUpload) { UserDefaults.standard.set(newValue, forKey: Self.autoUploadKey) } }
    }
    private static let autoUploadKey = "account.autoUpload"
    /// Only matches started after this moment are uploaded automatically (no surprise bulk upload).
    private static let autoUploadSinceKey = "account.autoUploadSince"

    @ObservationIgnored let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )
    @ObservationIgnored private var authTask: Task<Void, Never>?

    var userID: UUID? { client.auth.currentUser?.id }

    /// Where the sign-in link in the e-mail leads: opens this app (URL scheme in Info.plist).
    /// Must also be listed in Supabase under Authentication → URL Configuration → Redirect URLs.
    static let loginRedirect = URL(string: "pointcheck://login")!
    /// The "Passwort vergessen" link opens the app here, so it can tell reset from sign-in.
    /// Must also be listed in Supabase under Redirect URLs.
    static let resetRedirect = URL(string: "pointcheck://reset-password")!
    @ObservationIgnored private var pendingPasswordReset = false

    func start() {
        guard authTask == nil else { return }
        authTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .passwordRecovery:
                    state = .resettingPassword
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if session != nil {
                        if pendingPasswordReset || state == .resettingPassword {
                            state = .resettingPassword
                        } else {
                            state = .signedIn
                        }
                        await refresh()
                    } else {
                        state = .signedOut
                    }
                case .signedOut:
                    state = .signedOut
                    clear()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign in with e-mail and password

    enum SignInError: LocalizedError {
        case wrongCredentials
        case alreadyRegistered
        case weakPassword
        case emailNotConfirmed

        var errorDescription: String? {
            switch self {
            case .wrongCredentials: "E-Mail-Adresse oder Passwort stimmt nicht."
            case .alreadyRegistered: "Zu dieser E-Mail-Adresse gibt es schon ein Konto. Wechsle zu „Anmelden“."
            case .weakPassword: "Das Passwort braucht mindestens 8 Zeichen."
            case .emailNotConfirmed: "Bitte bestätige zuerst deine E-Mail-Adresse über den Link in der E-Mail."
            }
        }
    }

    /// Creates an account. With e-mail confirmation switched off in Supabase the person is
    /// signed in right away; otherwise a confirmation mail is sent first.
    func register(email: String, password: String, displayName: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password.count >= 8 else { throw SignInError.weakPassword }
        do {
            let response = try await client.auth.signUp(
                email: address,
                password: password,
                data: name.isEmpty ? nil : ["display_name": .string(name)],
                redirectTo: Self.loginRedirect
            )
            if case .user = response {
                // Confirmation required – try signing in to give a clear message.
                try await signIn(email: address, password: password)
            }
        } catch let error as AuthError {
            switch error.errorCode {
            case .userAlreadyExists: throw SignInError.alreadyRegistered
            case .weakPassword: throw SignInError.weakPassword
            default: throw error
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            try await client.auth.signIn(email: address, password: password)
        } catch let error as AuthError {
            switch error.errorCode {
            case .invalidCredentials: throw SignInError.wrongCredentials
            case .emailNotConfirmed: throw SignInError.emailNotConfirmed
            default: throw error
            }
        }
        state = .signedIn
        await refresh()
    }

    /// Sends the reset mail; its link opens the app at pointcheck://reset-password.
    func requestPasswordReset(email: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await client.auth.resetPasswordForEmail(address, redirectTo: Self.resetRedirect)
    }

    /// Changes the password of the signed-in user (settings, or after a reset link).
    func updatePassword(_ password: String) async throws {
        guard password.count >= 8 else { throw SignInError.weakPassword }
        do {
            try await client.auth.update(user: UserAttributes(password: password))
        } catch let error as AuthError where error.errorCode == .weakPassword {
            throw SignInError.weakPassword
        }
    }

    /// After the reset link: set the new password and enter the app.
    func setNewPassword(_ password: String) async throws {
        try await updatePassword(password)
        pendingPasswordReset = false
        state = .signedIn
        await refresh()
    }

    /// Gives up on the reset and signs out again.
    func cancelPasswordReset() async {
        pendingPasswordReset = false
        await signOut()
    }

    /// The sign-in link from the e-mail was tapped and opened the app.
    func handleOpenURL(_ url: URL) async {
        guard url.scheme == Self.loginRedirect.scheme else { return }
        let isReset = url.host == Self.resetRedirect.host || url.absoluteString.contains("type=recovery")
        pendingPasswordReset = isReset
        do {
            _ = try await client.auth.session(from: url)
            state = isReset ? .resettingPassword : .signedIn
            await refresh()
        } catch {
            pendingPasswordReset = false
            print("Sign-in link failed: \(error)")
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        state = .signedOut
        clear()
    }

    private func clear() {
        profile = nil
        openConfirmations = []
        uploads = [:]
        ratingHistory = []
        followRequests = []
        recentFollowers = []
        feed = []
        feedHasMore = false
        suggestions = []
        rematches = []
        reactions = [:]
        commentCounts = [:]
        foreignMatches = []
        foreignIDs = []
    }

    /// Watch matches plus confirmed matches from co-players, without duplicates.
    func allMatches(local: [MatchSummary]) -> [MatchSummary] {
        let localIDs = Set(local.map(\.id))
        return local + foreignMatches.filter { !localIDs.contains($0.id) }
    }

    // MARK: - Loading

    /// Loads everything independently, so one missing piece (e.g. a migration not yet
    /// run in Supabase) does not block the rest.
    func refresh() async {
        guard let userID else { return }

        if let loaded: RemoteProfile = await load("profile", {
            try await self.client.from("profiles").select().eq("id", value: userID).single().execute().value
        }) {
            profile = loaded
            let key = "\(Self.lastSeenRatingKey).\(userID.uuidString)"
            if let seen = UserDefaults.standard.object(forKey: key) as? Double {
                pendingRatingDelta = loaded.rating - seen
            } else {
                UserDefaults.standard.set(loaded.rating, forKey: key)
            }
        }

        if let loaded: [OpenConfirmation] = await load("open confirmations", {
            try await self.client.from("open_confirmations").select()
                .order("started_at", ascending: false).execute().value
        }) {
            openConfirmations = loaded
        }

        if let feed: [FeedMatch] = await load("match feed", {
            try await self.client.rpc("my_match_feed").execute().value
        }) {
            uploads = Dictionary(feed.filter(\.createdByMe).map { ($0.matchID, $0.status) }, uniquingKeysWith: { a, _ in a })
            foreignIDs = Set(feed.filter { !$0.createdByMe }.map(\.matchID))
            foreignMatches = feed.filter { !$0.createdByMe && $0.status == .confirmed }.map(\.summary)
        }

        if let loaded: [PersonRow] = await load("follow requests", {
            try await self.client.rpc("follow_requests").execute().value
        }) {
            followRequests = loaded
        }

        if let loaded: [PersonRow] = await load("recent followers", {
            try await self.client.rpc("recent_followers").execute().value
        }) {
            recentFollowers = loaded
        }

        await loadFeed()
        await loadRematches()

        if let loaded: [RatingHistoryRow] = await load("rating history", {
            try await self.client.from("rating_history").select("id, rating_before, rating_after, created_at")
                .eq("profile_id", value: userID).order("created_at").execute().value
        }) {
            ratingHistory = loaded
        }
    }

    private func load<T>(_ what: String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            print("Loading \(what) failed: \(error)")
            return nil
        }
    }

    // MARK: - Profile

    enum ProfileError: LocalizedError {
        case invalidUsername
        case usernameTaken

        var errorDescription: String? {
            switch self {
            case .invalidUsername: "Der Benutzername braucht 3–20 Zeichen: Kleinbuchstaben, Zahlen, Punkt oder Unterstrich."
            case .usernameTaken: "Dieser Benutzername ist schon vergeben."
            }
        }
    }

    private struct ProfilePatch: Encodable {
        var displayName: String
        var username: String?
        var visibility: ProfileVisibility
        var bio: String?
        var homeClub: String?

        enum CodingKeys: String, CodingKey {
            case username, visibility, bio
            case displayName = "display_name"
            case homeClub = "home_club"
        }
    }

    func updateProfile(displayName: String, username: String, visibility: ProfileVisibility,
                       bio: String = "", homeClub: String = "") async throws {
        guard let userID else { return }
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanName.isEmpty, cleanName.range(of: #"^[a-z0-9_.]{3,20}$"#, options: .regularExpression) == nil {
            throw ProfileError.invalidUsername
        }
        let cleanBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClub = homeClub.trimmingCharacters(in: .whitespacesAndNewlines)
        let patch = ProfilePatch(
            displayName: String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)),
            username: cleanName.isEmpty ? nil : cleanName,
            visibility: visibility,
            bio: cleanBio.isEmpty ? nil : String(cleanBio.prefix(160)),
            homeClub: cleanClub.isEmpty ? nil : String(cleanClub.prefix(60))
        )
        do {
            try await client.from("profiles").update(patch).eq("id", value: userID).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            throw ProfileError.usernameTaken
        }
        await refresh()
    }

    func findProfile(username: String) async -> FoundProfile? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !name.isEmpty else { return nil }
        let found: [FoundProfile]? = try? await client
            .rpc("find_profile", params: ["p_username": name])
            .execute()
            .value
        return found?.first
    }

    // MARK: - Matches

    enum UploadError: LocalizedError {
        case notDecided
        case unknownUser(String)
        case linkedYourself

        var errorDescription: String? {
            switch self {
            case .notDecided: "Nur gewonnene oder verlorene Matches können eingetragen werden."
            case .unknownUser(let name): "Es gibt keinen Spieler mit dem Benutzernamen „\(name)“."
            case .linkedYourself: "Du kannst dich nicht selbst als Partner oder Gegner eintragen."
            }
        }
    }

    /// Uploads a match from the watch and links partner/opponents by username.
    /// Names without an account are stored as guests (they cannot confirm).
    func upload(_ match: MatchSummary, partner: String, opponents: [String]) async throws {
        guard let row = MatchUpload(match) else { throw UploadError.notDecided }

        // Resolve usernames before writing anything.
        var players: [MatchPlayerUpload] = []
        for (slot, name) in [(2, partner)] + opponents.prefix(2).enumerated().map({ ($0.offset + 3, $0.element) }) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("@") {
                guard let found = await findProfile(username: trimmed) else {
                    throw UploadError.unknownUser(String(trimmed.dropFirst()))
                }
                guard found.id != userID else { throw UploadError.linkedYourself }
                players.append(MatchPlayerUpload(matchID: match.id, slot: slot, profileID: found.id))
            } else {
                players.append(MatchPlayerUpload(matchID: match.id, slot: slot, guestName: String(trimmed.prefix(40))))
            }
        }

        do {
            try await client.from("matches").insert(row).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            // Already uploaded – only (re)link players below.
        }
        // Replace partner/opponent links (an upsert would need UPDATE rights on the key columns).
        // Only possible while the match is still waiting for confirmation.
        try await client.from("match_players")
            .delete()
            .eq("match_id", value: match.id)
            .gt("slot", value: 1)
            .execute()
        if !players.isEmpty {
            try await client.from("match_players").insert(players).execute()
        }
        await refresh()
    }

    func confirm(_ confirmation: OpenConfirmation) async throws {
        try await client.rpc("confirm_match", params: ["m": confirmation.matchID]).execute()
        await refresh()
    }

    func reject(_ confirmation: OpenConfirmation) async throws {
        try await client.rpc("dispute_match", params: ["m": confirmation.matchID]).execute()
        await refresh()
    }

    // MARK: - Automatic upload

    /// Uploads finished watch matches that are not on the server yet (without links –
    /// partner and opponents can be added in the match details).
    func uploadNewMatches(_ local: [MatchSummary]) async {
        guard state == .signedIn, autoUpload else { return }
        let defaults = UserDefaults.standard
        let since: Date
        if let stored = defaults.object(forKey: Self.autoUploadSinceKey) as? Date {
            since = stored
        } else {
            // First time: start from now, older history stays private until uploaded by hand.
            since = .now
            defaults.set(since, forKey: Self.autoUploadSinceKey)
        }
        let pending = local.filter {
            $0.isDecided && $0.startDate >= since && uploads[$0.id] == nil && !foreignIDs.contains($0.id)
        }
        guard !pending.isEmpty else { return }
        for match in pending {
            guard let row = MatchUpload(match) else { continue }
            do {
                try await client.from("matches").insert(row).execute()
            } catch let error as PostgrestError where error.code == "23505" {
                // already there
            } catch {
                print("Automatic upload failed: \(error)")
                return
            }
        }
        await refresh()
    }

    // MARK: - Images (Supabase Storage)

    enum Bucket: String { case avatars, posts }

    /// Public URL of a stored image, or `nil` without a path.
    func imageURL(_ path: String?, bucket: Bucket) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        // Images shipped inside the app (demo player): "bundle:<name>"
        if path.hasPrefix("bundle:") {
            return Bundle.main.url(forResource: String(path.dropFirst("bundle:".count)), withExtension: "jpg")
        }
        return try? client.storage.from(bucket.rawValue).getPublicURL(path: path)
    }

    /// Uploads a JPEG into my folder of the bucket and returns its path.
    private func uploadImage(_ data: Data, bucket: Bucket, name: String) async throws -> String {
        guard let userID else { throw UploadError.notDecided }
        let path = "\(userID.uuidString.lowercased())/\(name).jpg"
        try await client.storage.from(bucket.rawValue).upload(
            path,
            data: data,
            options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
        )
        return path
    }

    func uploadAvatar(_ jpeg: Data) async throws {
        guard let userID else { return }
        // New file name each time, so cached old photos are not shown.
        let path = try await uploadImage(jpeg, bucket: .avatars, name: "avatar-\(Int(Date.now.timeIntervalSince1970))")
        try await client.from("profiles").update(["avatar_path": path]).eq("id", value: userID).execute()
        await refresh()
    }

    // MARK: - Following

    enum FollowError: LocalizedError {
        case notFound(String)
        case yourself

        var errorDescription: String? {
            switch self {
            case .notFound(let name): "Es gibt keinen Spieler mit dem Benutzernamen „\(name)“."
            case .yourself: "Das bist du selbst."
            }
        }
    }

    /// Follows a profile. Returns the new relation (`following` or `pending`).
    @discardableResult
    func follow(_ profileID: UUID) async throws -> FollowRelation {
        let status: String = try await client.rpc("follow", params: ["p_profile": profileID]).execute().value
        await refresh()
        return status == "accepted" ? .following : .pending
    }

    func unfollow(_ profileID: UUID) async throws {
        try await client.rpc("unfollow", params: ["p_profile": profileID]).execute()
        await refresh()
    }

    func acceptFollow(_ follower: PersonRow) async throws {
        try await client.rpc("accept_follow", params: ["p_follower": follower.profileID]).execute()
        await refresh()
    }

    func removeFollower(_ follower: PersonRow) async throws {
        try await client.rpc("remove_follower", params: ["p_follower": follower.profileID]).execute()
        await refresh()
    }

    func profilePage(_ profileID: UUID) async throws -> ProfilePage? {
        let rows: [ProfilePage] = try await client.rpc("profile_page", params: ["p_profile": profileID]).execute().value
        return rows.first
    }

    func followers(of profileID: UUID) async -> [PersonRow] {
        (try? await client.rpc("followers_of", params: ["p_profile": profileID]).execute().value) ?? []
    }

    func following(of profileID: UUID) async -> [PersonRow] {
        (try? await client.rpc("following_of", params: ["p_profile": profileID]).execute().value) ?? []
    }

    func rememberSearch(_ person: PersonRow) {
        var list = recentSearches.filter { $0.profileID != person.profileID }
        var entry = person
        entry.reason = nil
        entry.relation = nil
        list.insert(entry, at: 0)
        recentSearches = Array(list.prefix(10))
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(data, forKey: Self.recentSearchesKey)
        }
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
    }

    private static func loadRecentSearches() -> [PersonRow] {
        guard let data = UserDefaults.standard.data(forKey: recentSearchesKey) else { return [] }
        return (try? JSONDecoder().decode([PersonRow].self, from: data)) ?? []
    }

    func search(_ query: String) async -> [PersonRow] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return (try? await client.rpc("search_profiles", params: ["p_query": query]).execute().value) ?? []
    }

    func loadSuggestions() async {
        if let loaded: [PersonRow] = await load("suggestions", {
            try await self.client.rpc("suggested_profiles").execute().value
        }) {
            suggestions = loaded
        }
    }

    // MARK: - Feed & posts

    /// The floating "+24" was shown – remember the current rating as seen.
    func acknowledgeRatingDelta() {
        guard let userID, let profile else { return }
        UserDefaults.standard.set(profile.rating, forKey: "\(Self.lastSeenRatingKey).\(userID.uuidString)")
        pendingRatingDelta = 0
    }

    private static let feedPageSize = 20

    private struct FeedParams: Encodable {
        var p_limit: Int
        var p_before: Date?
    }

    func loadFeed() async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        if let page: [FeedItem] = await load("feed", {
            try await self.client.rpc("home_feed", params: FeedParams(p_limit: Self.feedPageSize, p_before: nil)).execute().value
        }) {
            feed = page
            feedHasMore = page.count == Self.feedPageSize
            await loadSocialCounts(for: page)
        }
    }

    private func loadSocialCounts(for items: [FeedItem]) async {
        await loadReactions(for: items.filter { $0.kind == .post }.map(\.id))
        await loadCommentCounts(posts: items.filter { $0.kind == .post }.map(\.id),
                                matches: items.compactMap { $0.kind == .match ? $0.id : $0.match?.matchID })
    }

    func loadMoreFeed() async {
        guard feedHasMore, let last = feed.last else { return }
        if let page: [FeedItem] = await load("feed page", {
            try await self.client.rpc("home_feed", params: FeedParams(p_limit: Self.feedPageSize, p_before: last.createdAt)).execute().value
        }) {
            feed += page
            feedHasMore = page.count == Self.feedPageSize
            await loadSocialCounts(for: page)
        }
    }

    private struct ProfileListParams: Encodable {
        var p_profile: UUID
        var p_limit: Int = 30
        var p_before: Date?
    }

    func profilePosts(_ profileID: UUID, before: Date? = nil) async -> [ProfilePost] {
        (try? await client.rpc("profile_posts", params: ProfileListParams(p_profile: profileID, p_before: before)).execute().value) ?? []
    }

    func profileResults(_ profileID: UUID, before: Date? = nil) async -> [ProfileResult] {
        (try? await client.rpc("profile_results", params: ProfileListParams(p_profile: profileID, p_before: before)).execute().value) ?? []
    }

    private struct PostInsert: Encodable {
        var text: String
        var imagePath: String?
        var matchID: UUID?

        enum CodingKeys: String, CodingKey {
            case text
            case imagePath = "image_path"
            case matchID = "match_id"
        }
    }

    /// Creates a post. A match can only be attached if it is on the server (uploaded).
    func createPost(text: String, image: Data?, matchID: UUID?) async throws {
        var imagePath: String?
        if let image {
            imagePath = try await uploadImage(image, bucket: .posts, name: UUID().uuidString.lowercased())
        }
        let cleanText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        try await client.from("posts").insert(PostInsert(text: cleanText, imagePath: imagePath, matchID: matchID)).execute()
        await loadFeed()
    }

    func deletePost(_ postID: UUID) async throws {
        try await client.from("posts").delete().eq("id", value: postID).execute()
        await loadFeed()
    }

    /// Things waiting for me: follow requests, results to confirm, rematch requests.
    var activityCount: Int { followRequests.count + openConfirmations.count + rematches.filter { $0.incoming && $0.status == .pending }.count }

    // MARK: - Reactions & comments

    private(set) var reactions: [UUID: ReactionSummary] = [:]
    private(set) var commentCounts: [UUID: Int] = [:]

    func loadReactions(for postIDs: [UUID]) async {
        guard !postIDs.isEmpty else { return }
        if let rows: [ReactionSummary] = await load("reactions", {
            try await self.client.rpc("reaction_summary", params: ["p_posts": postIDs]).execute().value
        }) {
            for row in rows { reactions[row.postID] = row }
        }
    }

    func loadCommentCounts(posts: [UUID], matches: [UUID]) async {
        guard !posts.isEmpty || !matches.isEmpty else { return }
        struct Params: Encodable { var p_posts: [UUID]; var p_matches: [UUID] }
        if let rows: [CommentCount] = await load("comment counts", {
            try await self.client.rpc("comment_counts", params: Params(p_posts: posts, p_matches: matches)).execute().value
        }) {
            for row in rows {
                if let id = row.postID ?? row.matchID { commentCounts[id] = row.comments }
            }
        }
    }

    /// Toggles my 👏 on a post; optimistic update.
    func toggleClap(_ postID: UUID) async {
        let before = reactions[postID] ?? ReactionSummary(postID: postID, claps: 0, clapped: false)
        reactions[postID] = ReactionSummary(postID: postID, claps: before.claps + (before.clapped ? -1 : 1), clapped: !before.clapped)
        do {
            if before.clapped {
                try await client.from("reactions").delete().eq("post_id", value: postID).eq("profile_id", value: userID ?? UUID()).execute()
            } else {
                try await client.from("reactions").insert(["post_id": postID]).execute()
            }
        } catch {
            reactions[postID] = before
        }
    }

    func reactors(of postID: UUID) async -> [PersonRow] {
        (try? await client.rpc("reactors", params: ["p_post": postID]).execute().value) ?? []
    }

    func comments(post: UUID? = nil, match: UUID? = nil) async -> [Comment] {
        struct Params: Encodable { var p_post: UUID?; var p_match: UUID? }
        return (try? await client.rpc("comments_for", params: Params(p_post: post, p_match: match)).execute().value) ?? []
    }

    func addComment(_ text: String, post: UUID? = nil, match: UUID? = nil) async throws {
        struct Insert: Encodable {
            var post_id: UUID?
            var match_id: UUID?
            var text: String
        }
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !clean.isEmpty else { return }
        try await client.from("comments").insert(Insert(post_id: post, match_id: match, text: clean)).execute()
        if let id = post ?? match { commentCounts[id, default: 0] += 1 }
    }

    func deleteComment(_ id: UUID, target: UUID) async throws {
        try await client.from("comments").delete().eq("id", value: id).execute()
        commentCounts[target] = max(0, (commentCounts[target] ?? 1) - 1)
    }

    // MARK: - Rematches

    private(set) var rematches: [RematchRequest] = []

    func loadRematches() async {
        if let rows: [RematchRequest] = await load("rematches", {
            try await self.client.rpc("my_rematches").execute().value
        }) {
            rematches = rows
        }
    }

    func proposeRematch(to profileID: UUID, matchID: UUID?, at date: Date, note: String) async throws {
        struct Insert: Encodable {
            var to_id: UUID
            var match_id: UUID?
            var proposed_at: Date
            var note: String?
        }
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.from("rematch_requests")
            .insert(Insert(to_id: profileID, match_id: matchID, proposed_at: date, note: clean.isEmpty ? nil : String(clean.prefix(200))))
            .execute()
        await loadRematches()
    }

    func respondRematch(_ request: RematchRequest, accept: Bool) async throws {
        struct Params: Encodable { var p_request: UUID; var p_accept: Bool }
        try await client.rpc("respond_rematch", params: Params(p_request: request.id, p_accept: accept)).execute()
        await loadRematches()
    }

    func withdrawRematch(_ request: RematchRequest) async throws {
        try await client.from("rematch_requests").delete().eq("id", value: request.id).execute()
        await loadRematches()
    }

    // MARK: - Games wanted

    func openGames(club: String? = nil) async -> [GameWanted] {
        struct Params: Encodable { var p_club: String? }
        return (try? await client.rpc("open_games", params: Params(p_club: club)).execute().value) ?? []
    }

    func createGame(startsAt: Date, club: String, court: String, playersNeeded: Int, note: String) async throws -> UUID {
        struct Insert: Encodable {
            var id: UUID
            var starts_at: Date
            var club: String?
            var court: String?
            var players_needed: Int
            var note: String?
        }
        let id = UUID()
        func clean(_ s: String, _ max: Int) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : String(t.prefix(max))
        }
        try await client.from("games_wanted").insert(Insert(
            id: id, starts_at: startsAt, club: clean(club, 60), court: clean(court, 20),
            players_needed: min(3, max(1, playersNeeded)), note: clean(note, 200)
        )).execute()
        return id
    }

    func joinGame(_ game: GameWanted) async throws {
        try await client.from("game_joins").insert(["game_id": game.id]).execute()
    }

    func leaveGame(_ game: GameWanted) async throws {
        try await client.from("game_joins").delete().eq("game_id", value: game.id).eq("profile_id", value: userID ?? UUID()).execute()
    }

    func cancelGame(_ game: GameWanted) async throws {
        try await client.from("games_wanted").delete().eq("id", value: game.id).execute()
    }

    // MARK: - Club & head-to-head

    func clubRanking(_ club: String) async -> [ClubMember] {
        (try? await client.rpc("club_ranking", params: ["p_club": club]).execute().value) ?? []
    }

    func clubActivity(_ club: String) async -> ClubActivity? {
        let rows: [ClubActivity]? = try? await client.rpc("club_activity", params: ["p_club": club]).execute().value
        return rows?.first
    }

    func headToHead(_ profileID: UUID) async -> HeadToHead? {
        let rows: [HeadToHead]? = try? await client.rpc("head_to_head", params: ["p_other": profileID]).execute().value
        return rows?.first
    }

    // MARK: - Push (device token; delivery needs the Apple Developer Program)

    func registerDeviceToken(_ token: String) async {
        struct Row: Encodable { var token: String; var platform: String }
        _ = try? await client.from("device_tokens").upsert(Row(token: token, platform: "ios")).execute()
    }

    // MARK: - Delete account

    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut()
        state = .signedOut
        clear()
    }

    func leaderboard() async -> [LeaderboardRow] {
        (try? await client.from("leaderboard").select().limit(100).execute().value) ?? []
    }
}
