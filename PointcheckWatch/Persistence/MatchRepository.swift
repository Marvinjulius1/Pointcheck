import Foundation
import PadelScoring
import SwiftData

/// Thin wrapper around SwiftData so the controller never touches the context directly.
@MainActor
struct MatchRepository {
    let context: ModelContext

    func record(id: UUID) -> MatchRecord? {
        var descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates or updates the record for a running match. Returns the record id,
    /// or `nil` if the match has no points (an empty match is not kept).
    @discardableResult
    func sync(_ state: MatchState, recordID: UUID?) -> UUID? {
        guard state.hasStarted else {
            if let recordID { delete(id: recordID) }
            return nil
        }
        let record: MatchRecord
        if let recordID, let existing = self.record(id: recordID) {
            record = existing
        } else {
            record = MatchRecord(rules: state.rules)
            context.insert(record)
        }
        record.apply(state)
        save()
        return record.id
    }

    func complete(id: UUID) {
        record(id: id)?.markCompleted()
        save()
    }

    func delete(id: UUID) {
        guard let record = record(id: id) else { return }
        context.delete(record)
        save()
    }

    func save() {
        do {
            try context.save()
        } catch {
            print("SwiftData save failed: \(error)")
        }
    }
}
