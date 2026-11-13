import Foundation
import PadelStats

/// A built-in demo player, so transitions and profile pages can be tried out
/// before there are real followers. Lives only on this device.
enum DemoProfile {
    static let id = UUID(uuidString: "DE100000-0000-4000-8000-00000000DE10")!
    static let name = "Demo Spieler"

    static var page: ProfilePage {
        ProfilePage(
            id: id,
            displayName: name,
            username: "demo",
            avatarPath: nil,
            bio: "Zum Ausprobieren: tipp auf mein Foto, meine Ergebnisse und Beiträge.",
            homeClub: "Padel Arena Musterstadt",
            visibility: .public,
            isVisible: true,
            relation: .none,
            followsMe: false,
            followers: 128,
            following: 64,
            posts: 3,
            rating: 1612,
            ratedMatches: 27,
            ratedWins: 17,
            currentStreak: 3
        )
    }

    static var results: [ProfileResult] {
        let now = Date.now
        func set(_ me: Int, _ opp: Int, tb: (Int, Int)? = nil, superTB: Bool = false) -> SetScore {
            SetScore(games: TeamScore(me: me, opponent: opp), tiebreak: tb.map { TeamScore(me: $0.0, opponent: $0.1) }, isSuperTiebreak: superTB)
        }
        return [
            ProfileResult(matchID: UUID(), startedAt: now.addingTimeInterval(-2 * 86_400), endedAt: now.addingTimeInterval(-2 * 86_400 + 5400),
                          sets: [set(6, 4), set(7, 6, tb: (7, 4))], winnerSide: "a", playerSide: "a",
                          partnerName: "Lena", opponentNames: "Max & Tom"),
            ProfileResult(matchID: UUID(), startedAt: now.addingTimeInterval(-5 * 86_400), endedAt: now.addingTimeInterval(-5 * 86_400 + 4800),
                          sets: [set(6, 2), set(3, 6), set(1, 0, tb: (10, 8), superTB: true)], winnerSide: "a", playerSide: "a",
                          partnerName: "Lena", opponentNames: "Ali & Jonas"),
            ProfileResult(matchID: UUID(), startedAt: now.addingTimeInterval(-9 * 86_400), endedAt: now.addingTimeInterval(-9 * 86_400 + 5000),
                          sets: [set(6, 3), set(6, 4)], winnerSide: "a", playerSide: "a",
                          partnerName: "Paul", opponentNames: "Mara & Sofia"),
            ProfileResult(matchID: UUID(), startedAt: now.addingTimeInterval(-14 * 86_400), endedAt: now.addingTimeInterval(-14 * 86_400 + 6000),
                          sets: [set(4, 6), set(6, 7, tb: (5, 7))], winnerSide: "b", playerSide: "a",
                          partnerName: "Paul", opponentNames: "Nina & Elif"),
        ]
    }

    static var posts: [ProfilePost] {
        [
            ProfilePost(id: UUID(), createdAt: .now.addingTimeInterval(-3600 * 5),
                        text: "Erstes Match der Woche – und gleich ein Tiebreak im zweiten Satz. Nerven gehalten!",
                        imagePath: nil,
                        match: AttachedMatch(matchID: UUID(), startedAt: .now.addingTimeInterval(-3600 * 6),
                                             sets: [SetScore(games: TeamScore(me: 6, opponent: 4)),
                                                    SetScore(games: TeamScore(me: 7, opponent: 6), tiebreak: TeamScore(me: 7, opponent: 4))],
                                             winnerSide: "a", authorSide: "a", partnerName: "Lena", opponentNames: "Max & Tom")),
            ProfilePost(id: UUID(), createdAt: .now.addingTimeInterval(-86_400 * 3),
                        text: "Wer hat Lust auf ein Mixed am Samstag? Court 2 ist gebucht.", imagePath: nil, match: nil),
            ProfilePost(id: UUID(), createdAt: .now.addingTimeInterval(-86_400 * 8),
                        text: "Neuer Schläger, neues Glück.", imagePath: nil, match: nil),
        ]
    }

    /// Entry for the avatar row and the feed while nothing real is there yet.
    static var person: PersonRow {
        PersonRow(profileID: id, displayName: name, username: "demo", avatarPath: nil, homeClub: "Padel Arena Musterstadt",
                  rating: 1612, relation: .none, reason: "Zum Ausprobieren", requestedAt: nil, followedAt: nil)
    }

    static var feedItem: FeedItem {
        let post = posts[0]
        return FeedItem(kind: .post, id: post.id, createdAt: post.createdAt, authorID: id, authorName: name,
                        authorUsername: "demo", authorAvatar: nil, text: post.text, imagePath: nil, match: post.match)
    }
}
