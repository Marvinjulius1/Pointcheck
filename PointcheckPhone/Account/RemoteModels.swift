import Foundation
import PadelStats

// Rows as returned by the Supabase API (see supabase/migrations).

enum ProfileVisibility: String, Codable, CaseIterable, Identifiable {
    case `public`
    case followers

    var id: Self { self }

    var title: String {
        switch self {
        case .public: "Öffentlich"
        case .followers: "Privat"
        }
    }

    var explanation: String {
        switch self {
        case .public: "Jeder kann dir folgen und sieht dein Profil, deine Spielstärke und deine Ergebnisse. Du erscheinst in Ranglisten."
        case .followers: "Du bestätigst jede Folge-Anfrage selbst. Nur deine Follower sehen Profil, Ergebnisse und Beiträge."
        }
    }
}

struct RemoteProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var username: String?
    var avatarPath: String?
    var bio: String?
    var homeClub: String?
    var visibility: ProfileVisibility
    var rating: Double
    var ratedMatches: Int
    var ratedWins: Int

    var level: Double { PadelLevel.level(for: rating) }

    enum CodingKeys: String, CodingKey {
        case id, username, visibility, rating, bio
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case homeClub = "home_club"
        case ratedMatches = "rated_matches"
        case ratedWins = "rated_wins"
    }
}

/// How I relate to another profile.
enum FollowRelation: String, Codable {
    case none, pending, following, `self`

    var buttonTitle: String {
        switch self {
        case .none: "Folgen"
        case .pending: "Angefragt"
        case .following: "Folge ich"
        case .self: "Profil bearbeiten"
        }
    }
}

/// A compact person row as returned by the list functions (followers, following,
/// requests, search, suggestions). Optional fields depend on the function.
struct PersonRow: Codable, Identifiable, Equatable {
    var profileID: UUID
    var displayName: String
    var username: String?
    var avatarPath: String?
    var homeClub: String?
    var rating: Double?
    var relation: FollowRelation?
    var reason: String?
    var requestedAt: Date?
    var followedAt: Date?

    var id: UUID { profileID }
    var level: Double? { rating.map(PadelLevel.level(for:)) }

    enum CodingKeys: String, CodingKey {
        case username, rating, relation, reason
        case profileID = "profile_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case homeClub = "home_club"
        case requestedAt = "requested_at"
        case followedAt = "followed_at"
    }
}

/// Everything the profile screen shows (`profile_page`).
struct ProfilePage: Decodable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var username: String?
    var avatarPath: String?
    var bio: String?
    var homeClub: String?
    var visibility: ProfileVisibility
    var isVisible: Bool
    var relation: FollowRelation
    var followsMe: Bool
    var followers: Int
    var following: Int
    var posts: Int
    var rating: Double?
    var ratedMatches: Int?
    var ratedWins: Int?
    var currentStreak: Int?

    var level: Double? { rating.map(PadelLevel.level(for:)) }
    var winRate: Double? {
        guard let ratedMatches, ratedMatches > 0, let ratedWins else { return nil }
        return Double(ratedWins) / Double(ratedMatches)
    }

    enum CodingKeys: String, CodingKey {
        case id, username, bio, visibility, relation, followers, following, posts, rating
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case homeClub = "home_club"
        case isVisible = "is_visible"
        case followsMe = "follows_me"
        case ratedMatches = "rated_matches"
        case ratedWins = "rated_wins"
        case currentStreak = "current_streak"
    }
}

/// Match data attached to a feed item or post, from the author's side.
struct AttachedMatch: Equatable {
    var matchID: UUID
    var startedAt: Date
    var sets: [SetScore]
    var authorWon: Bool
    var partnerName: String?
    var opponentNames: String?

    /// "6:4  3:6  [10:8]" from the author's side.
    var resultText: String {
        sets.map(\.resultText).joined(separator: "  ")
    }

    var setsWon: TeamScore {
        sets.reduce(into: TeamScore.zero) { result, set in
            if let winner = set.winner { result[winner] += 1 }
        }
    }

    /// Builds from the raw columns; `authorSide` tells which side the stored sets belong to.
    init?(matchID: UUID?, startedAt: Date?, sets: [SetScore]?, winnerSide: String?, authorSide: String?,
          partnerName: String?, opponentNames: String?) {
        guard let matchID, let startedAt, let sets, let winnerSide, let authorSide else { return nil }
        self.matchID = matchID
        self.startedAt = startedAt
        self.sets = authorSide == "a" ? sets : sets.map(\.flipped)
        self.authorWon = winnerSide == authorSide
        self.partnerName = partnerName
        self.opponentNames = opponentNames
    }
}

/// One entry of the home feed (`home_feed`): a post or a confirmed match.
struct FeedItem: Decodable, Identifiable, Equatable {
    enum Kind: String, Decodable { case post, match }

    var kind: Kind
    var id: UUID
    var createdAt: Date
    var authorID: UUID
    var authorName: String
    var authorUsername: String?
    var authorAvatar: String?
    var text: String?
    var imagePath: String?
    var match: AttachedMatch?

    enum CodingKeys: String, CodingKey {
        case kind, id, text, sets
        case createdAt = "created_at"
        case authorID = "author_id"
        case authorName = "author_name"
        case authorUsername = "author_username"
        case authorAvatar = "author_avatar"
        case imagePath = "image_path"
        case matchID = "match_id"
        case startedAt = "started_at"
        case winnerSide = "winner_side"
        case authorSide = "author_side"
        case partnerName = "partner_name"
        case opponentNames = "opponent_names"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        authorName = try c.decode(String.self, forKey: .authorName)
        authorUsername = try c.decodeIfPresent(String.self, forKey: .authorUsername)
        authorAvatar = try c.decodeIfPresent(String.self, forKey: .authorAvatar)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        match = AttachedMatch(
            matchID: try c.decodeIfPresent(UUID.self, forKey: .matchID),
            startedAt: try c.decodeIfPresent(Date.self, forKey: .startedAt),
            sets: try c.decodeIfPresent([SetScore].self, forKey: .sets),
            winnerSide: try c.decodeIfPresent(String.self, forKey: .winnerSide),
            authorSide: try c.decodeIfPresent(String.self, forKey: .authorSide),
            partnerName: try c.decodeIfPresent(String.self, forKey: .partnerName),
            opponentNames: try c.decodeIfPresent(String.self, forKey: .opponentNames)
        )
    }
}

/// A post on a profile (`profile_posts`).
struct ProfilePost: Decodable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var text: String
    var imagePath: String?
    var match: AttachedMatch?

    enum CodingKeys: String, CodingKey {
        case id, text, sets
        case createdAt = "created_at"
        case imagePath = "image_path"
        case matchID = "match_id"
        case startedAt = "started_at"
        case winnerSide = "winner_side"
        case authorSide = "author_side"
        case partnerName = "partner_name"
        case opponentNames = "opponent_names"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        match = AttachedMatch(
            matchID: try c.decodeIfPresent(UUID.self, forKey: .matchID),
            startedAt: try c.decodeIfPresent(Date.self, forKey: .startedAt),
            sets: try c.decodeIfPresent([SetScore].self, forKey: .sets),
            winnerSide: try c.decodeIfPresent(String.self, forKey: .winnerSide),
            authorSide: try c.decodeIfPresent(String.self, forKey: .authorSide),
            partnerName: try c.decodeIfPresent(String.self, forKey: .partnerName),
            opponentNames: try c.decodeIfPresent(String.self, forKey: .opponentNames)
        )
    }
}

/// A confirmed result on a profile (`profile_results`), from that player's side.
struct ProfileResult: Decodable, Identifiable, Equatable {
    var matchID: UUID
    var startedAt: Date
    var endedAt: Date?
    var sets: [SetScore]
    var winnerSide: String
    var playerSide: String
    var partnerName: String?
    var opponentNames: String?

    var id: UUID { matchID }
    var playerWon: Bool { winnerSide == playerSide }
    var setsFromPlayer: [SetScore] { playerSide == "a" ? sets : sets.map(\.flipped) }
    var resultText: String { setsFromPlayer.map(\.resultText).joined(separator: "  ") }

    enum CodingKeys: String, CodingKey {
        case sets
        case matchID = "match_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case winnerSide = "winner_side"
        case playerSide = "player_side"
        case partnerName = "partner_name"
        case opponentNames = "opponent_names"
    }
}

/// Result of `find_profile(p_username)`.
struct FoundProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var username: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
    }
}

enum RemoteMatchStatus: String, Codable {
    case pending, confirmed, disputed

    var title: String {
        switch self {
        case .pending: "Wartet auf Bestätigung"
        case .confirmed: "Bestätigt"
        case .disputed: "Abgelehnt"
        }
    }
}

/// Insert payload for `matches` (creator = side A = "me").
struct MatchUpload: Encodable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var sets: [SetScore]
    var winnerSide: String
    var bestOf: Int
    var goldenPoint: Bool
    var superTiebreak: Bool

    init?(_ match: MatchSummary) {
        guard let winner = match.winner else { return nil }
        id = match.id
        startedAt = match.startDate
        endedAt = match.endDate
        sets = match.sets
        winnerSide = winner == .me ? "a" : "b"
        bestOf = match.bestOf
        goldenPoint = match.goldenPoint
        superTiebreak = match.superTiebreak
    }

    enum CodingKeys: String, CodingKey {
        case id, sets
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case winnerSide = "winner_side"
        case bestOf = "best_of"
        case goldenPoint = "golden_point"
        case superTiebreak = "super_tiebreak"
    }
}

struct MatchPlayerUpload: Encodable {
    var matchID: UUID
    var slot: Int
    var profileID: UUID?
    var guestName: String?

    enum CodingKeys: String, CodingKey {
        case slot
        case matchID = "match_id"
        case profileID = "profile_id"
        case guestName = "guest_name"
    }
}

/// A row of the `open_confirmations` view: a result someone else entered with me as opponent.
struct OpenConfirmation: Decodable, Identifiable {
    var matchID: UUID
    var creatorName: String
    var startedAt: Date
    var endedAt: Date?
    var sets: [SetScore]
    var winnerSide: String

    var id: UUID { matchID }

    /// Sets from my perspective (the creator stored them from theirs).
    var myResultText: String {
        sets.map { set -> String in
            if set.isSuperTiebreak, let tiebreak = set.tiebreak {
                return "[\(tiebreak.opponent):\(tiebreak.me)]"
            }
            return "\(set.games.opponent):\(set.games.me)"
        }
        .joined(separator: "  ")
    }

    var iWon: Bool { winnerSide == "b" }

    enum CodingKeys: String, CodingKey {
        case sets
        case matchID = "match_id"
        case creatorName = "creator_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case winnerSide = "winner_side"
    }
}

struct RatingHistoryRow: Decodable, Identifiable {
    var id: Int
    var ratingBefore: Double
    var ratingAfter: Double
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ratingBefore = "rating_before"
        case ratingAfter = "rating_after"
        case createdAt = "created_at"
    }
}

struct LeaderboardRow: Decodable, Identifiable {
    var id: UUID
    var displayName: String
    var username: String?
    var rating: Double
    var ratedMatches: Int

    var level: Double { PadelLevel.level(for: rating) }

    enum CodingKeys: String, CodingKey {
        case id, username, rating
        case displayName = "display_name"
        case ratedMatches = "rated_matches"
    }
}

/// Row of `my_match_feed()`: a match I play in, stored from side A's perspective.
struct FeedMatch: Decodable, Identifiable {
    var matchID: UUID
    var startedAt: Date
    var endedAt: Date?
    var sets: [SetScore]
    var winnerSide: String
    var status: RemoteMatchStatus
    var mySide: String
    var createdByMe: Bool
    var bestOf: Int
    var goldenPoint: Bool
    var superTiebreak: Bool
    var partnerName: String?
    var opponentNames: String?

    var id: UUID { matchID }

    /// The match as a summary from my perspective.
    var summary: MatchSummary {
        let sideA = MatchSummary(
            id: matchID,
            startDate: startedAt,
            endDate: endedAt,
            opponentName: opponentNames ?? "",
            partnerName: partnerName ?? "",
            sets: sets,
            winner: winnerSide == "a" ? .me : .opponent,
            isCompleted: true,
            bestOf: bestOf,
            goldenPoint: goldenPoint,
            superTiebreak: superTiebreak
        )
        guard mySide == "b" else { return sideA }
        // Names are already from my side; only the score needs turning around.
        var mine = sideA.flipped
        mine.opponentName = opponentNames ?? ""
        mine.partnerName = partnerName ?? ""
        return mine
    }

    enum CodingKeys: String, CodingKey {
        case sets, status
        case matchID = "match_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case winnerSide = "winner_side"
        case mySide = "my_side"
        case createdByMe = "created_by_me"
        case bestOf = "best_of"
        case goldenPoint = "golden_point"
        case superTiebreak = "super_tiebreak"
        case partnerName = "partner_name"
        case opponentNames = "opponent_names"
    }
}
