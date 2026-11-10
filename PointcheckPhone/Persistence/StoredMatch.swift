import Foundation
import PadelStats
import SwiftData

/// A match received from the watch. The watch is the source of truth;
/// the iPhone keeps a read-only copy for statistics.
@Model
final class StoredMatch {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var opponentName: String
    var partnerName: String
    /// JSON-encoded `[SetScore]`.
    var setsData: Data
    var winnerRaw: String?
    var isCompleted: Bool
    var bestOf: Int
    var goldenPoint: Bool
    var superTiebreak: Bool
    var receivedAt: Date

    init(_ summary: MatchSummary) {
        id = summary.id
        startDate = summary.startDate
        opponentName = ""
        partnerName = ""
        setsData = Data()
        isCompleted = true
        bestOf = 3
        goldenPoint = false
        superTiebreak = false
        receivedAt = .now
        update(from: summary)
    }

    func update(from summary: MatchSummary) {
        startDate = summary.startDate
        endDate = summary.endDate
        opponentName = summary.opponentName
        partnerName = summary.partnerName
        setsData = (try? JSONEncoder().encode(summary.sets)) ?? Data()
        winnerRaw = summary.winner?.rawValue
        isCompleted = summary.isCompleted
        bestOf = summary.bestOf
        goldenPoint = summary.goldenPoint
        superTiebreak = summary.superTiebreak
        receivedAt = .now
    }

    var summary: MatchSummary {
        MatchSummary(
            id: id,
            startDate: startDate,
            endDate: endDate,
            opponentName: opponentName,
            partnerName: partnerName,
            sets: (try? JSONDecoder().decode([SetScore].self, from: setsData)) ?? [],
            winner: winnerRaw.flatMap(Team.init(rawValue:)),
            isCompleted: isCompleted,
            bestOf: bestOf,
            goldenPoint: goldenPoint,
            superTiebreak: superTiebreak
        )
    }
}

/// Applies changes coming from the watch.
@MainActor
struct MatchStore {
    let context: ModelContext

    func upsert(_ summaries: [MatchSummary]) {
        for summary in summaries {
            let id = summary.id
            var descriptor = FetchDescriptor<StoredMatch>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: summary)
            } else {
                context.insert(StoredMatch(summary))
            }
        }
        save()
    }

    func delete(ids: [UUID]) {
        for id in ids {
            try? context.delete(model: StoredMatch.self, where: #Predicate { $0.id == id })
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("SwiftData save failed: \(error)")
        }
    }
}
