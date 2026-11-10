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
    private(set) var friends: [Friend] = []
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

    func sendCode(email: String, displayName: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.auth.signInWithOTP(
            email: address,
            redirectTo: Self.loginRedirect,
            data: name.isEmpty ? nil : ["display_name": .string(name)]
        )
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
        friends = []
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

        if let loaded: [Friend] = await load("friends", {
            try await self.client.rpc("my_friends").execute().value
        }) {
            friends = loaded
        }

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

        enum CodingKeys: String, CodingKey {
            case username, visibility
            case displayName = "display_name"
        }
    }

    func updateProfile(displayName: String, username: String, visibility: ProfileVisibility) async throws {
        guard let userID else { return }
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanName.isEmpty, cleanName.range(of: #"^[a-z0-9_.]{3,20}$"#, options: .regularExpression) == nil {
            throw ProfileError.invalidUsername
        }
        let patch = ProfilePatch(
            displayName: String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)),
            username: cleanName.isEmpty ? nil : cleanName,
            visibility: visibility
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

    // MARK: - Friends

    enum FriendError: LocalizedError {
        case notFound(String)
        case yourself

        var errorDescription: String? {
            switch self {
            case .notFound(let name): "Es gibt keinen Spieler mit dem Benutzernamen „\(name)“."
            case .yourself: "Das bist du selbst."
            }
        }
    }

    /// Sends a friend request by username. Returns `true` if you are friends right away
    /// (the other person had already asked you).
    @discardableResult
    func addFriend(username: String) async throws -> Bool {
        let name = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
        guard let found = await findProfile(username: name) else { throw FriendError.notFound(name) }
        guard found.id != userID else { throw FriendError.yourself }
        let status: String = try await client.rpc("request_friend", params: ["p_profile": found.id]).execute().value
        await refresh()
        return status == "accepted"
    }

    func acceptFriend(_ friend: Friend) async throws {
        try await client.rpc("accept_friend", params: ["p_profile": friend.profileID]).execute()
        await refresh()
    }

    func removeFriend(_ friend: Friend) async throws {
        try await client.rpc("remove_friend", params: ["p_profile": friend.profileID]).execute()
        await refresh()
    }

    func leaderboard() async -> [LeaderboardRow] {
        (try? await client.from("leaderboard").select().limit(100).execute().value) ?? []
    }
}
