import Foundation
import PadelStats

// Rows as returned by the Supabase API (see supabase/migrations).

enum ProfileVisibility: String, Codable, CaseIterable, Identifiable {
    case `public`
    case friends

    var id: Self { self }

    var title: String {
        switch self {
        case .public: "Öffentlich"
        case .friends: "Nur Freunde"
        }
    }

    var explanation: String {
        switch self {
        case .public: "Alle sehen dein Profil, deine Spielstärke und deine bestätigten Matches. Du erscheinst in Ranglisten."
        case .friends: "Nur deine Freunde sehen dein Profil und deine Matches. Du erscheinst in keiner öffentlichen Rangliste."
        }
    }
}

struct RemoteProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var username: String?
    var visibility: ProfileVisibility
    var rating: Double
    var ratedMatches: Int
    var ratedWins: Int

    var level: Double { PadelLevel.level(for: rating) }

    enum CodingKeys: String, CodingKey {
        case id, username, visibility, rating
        case displayName = "display_name"
        case ratedMatches = "rated_matches"
        case ratedWins = "rated_wins"
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

/// Row of `my_friends()`.
struct Friend: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable { case pending, accepted }

    var profileID: UUID
    var displayName: String
    var username: String?
    var rating: Double?
    var ratedMatches: Int?
    var status: Status
    /// The other person sent the request to me.
    var incoming: Bool

    var id: UUID { profileID }
    var level: Double? { rating.map(PadelLevel.level(for:)) }

    enum CodingKeys: String, CodingKey {
        case username, rating, status, incoming
        case profileID = "profile_id"
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
