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
        /// Code was sent to this address and must be entered.
        case awaitingCode(email: String)
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
    private(set) var suggestions: [PersonRow] = []
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

    func start() {
        guard authTask == nil else { return }
        authTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if session != nil {
                        state = .signedIn
                        await refresh()
                    } else if case .awaitingCode = state {
                        // keep the code screen
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

    // MARK: - Sign in with an e-mail code

    enum SignInError: LocalizedError {
        case noAccount
        case alreadyRegistered

        var errorDescription: String? {
            switch self {
            case .noAccount: "Zu dieser E-Mail-Adresse gibt es noch kein Konto. Wechsle zu „Registrieren“."
            case .alreadyRegistered: "Zu dieser E-Mail-Adresse gibt es schon ein Konto. Wechsle zu „Anmelden“."
            }
        }
    }

    /// Sends the sign-in code. `createAccount` = Registrieren (new account with name);
    /// otherwise only existing accounts receive a code.
    func sendCode(email: String, displayName: String, createAccount: Bool) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await client.auth.signInWithOTP(
                email: address,
                redirectTo: Self.loginRedirect,
                shouldCreateUser: createAccount,
                data: createAccount && !name.isEmpty ? ["display_name": .string(name)] : nil
            )
        } catch let error as AuthError {
            // Supabase answers "Signups not allowed for otp" when the address is unknown
            // and no account may be created.
            let unknownAddress = [.otpDisabled, .signupDisabled, .userNotFound].contains(error.errorCode)
                || error.message.localizedCaseInsensitiveContains("signups not allowed")
            if !createAccount, unknownAddress {
                throw SignInError.noAccount
            }
            throw error
        }
        state = .awaitingCode(email: address)
    }

    func verify(code: String) async throws {
        guard case .awaitingCode(let email) = state else { return }
        let token = code.filter(\.isNumber)
        try await client.auth.verifyOTP(email: email, token: token, type: .email)
        state = .signedIn
        await refresh()
    }

    /// The sign-in link from the e-mail was tapped and opened the app.
    func handleOpenURL(_ url: URL) async {
        guard url.scheme == Self.loginRedirect.scheme else { return }
        do {
            _ = try await client.auth.session(from: url)
            state = .signedIn
            await refresh()
        } catch {
            print("Sign-in link failed: \(error)")
        }
    }

    func cancelCode() {
        state = .signedOut
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

    private static let feedPageSize = 20

    private struct FeedParams: Encodable {
        var p_limit: Int
        var p_before: Date?
    }

    func loadFeed() async {
        if let page: [FeedItem] = await load("feed", {
            try await self.client.rpc("home_feed", params: FeedParams(p_limit: Self.feedPageSize, p_before: nil)).execute().value
        }) {
            feed = page
            feedHasMore = page.count == Self.feedPageSize
        }
    }

    func loadMoreFeed() async {
        guard feedHasMore, let last = feed.last else { return }
        if let page: [FeedItem] = await load("feed page", {
            try await self.client.rpc("home_feed", params: FeedParams(p_limit: Self.feedPageSize, p_before: last.createdAt)).execute().value
        }) {
            feed += page
            feedHasMore = page.count == Self.feedPageSize
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

    /// Things waiting for me: follow requests and results to confirm.
    var activityCount: Int { followRequests.count + openConfirmations.count }

    func leaderboard() async -> [LeaderboardRow] {
        (try? await client.from("leaderboard").select().limit(100).execute().value) ?? []
    }
}
