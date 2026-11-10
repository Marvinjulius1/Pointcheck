import PadelStats
import SwiftData
import SwiftUI

/// All matches, newest first. Swipe left on a row to delete, or clear everything at the bottom.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MatchRecord.startDate, order: .reverse) private var matches: [MatchRecord]
    @State private var showsClearDialog = false

    /// Everything except a match that is still being played.
    private var finishedMatches: [MatchRecord] {
        matches.filter { $0.status != .live }
    }

    var body: some View {
        List {
            ForEach(matches) { match in
                NavigationLink {
                    MatchDetailView(record: match)
                } label: {
                    MatchRow(record: match)
                }
            }
            .onDelete(perform: delete)

            if !finishedMatches.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showsClearDialog = true
                    } label: {
                        Label("Verlauf leeren", systemImage: "trash")
                    }
                }
            }
        }
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView(
                    "Noch keine Matches",
                    systemImage: "figure.tennis",
                    description: Text("Gespielte Matches erscheinen hier automatisch.")
                )
            }
        }
        .navigationTitle("Verlauf")
        .confirmationDialog("Verlauf leeren?", isPresented: $showsClearDialog, titleVisibility: .visible) {
            Button(finishedMatches.count == 1 ? "1 Match löschen" : "\(finishedMatches.count) Matches löschen", role: .destructive, action: clearHistory)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle beendeten Matches werden endgültig gelöscht. Ein laufendes Match bleibt erhalten.")
        }
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { matches[$0] }
        let ids = doomed.map(\.id)
        doomed.forEach { modelContext.delete($0) }
        try? modelContext.save()
        PhoneSync.shared.sendDeletion(ids)
    }

    private func clearHistory() {
        let ids = finishedMatches.map(\.id)
        finishedMatches.forEach { modelContext.delete($0) }
        try? modelContext.save()
        PhoneSync.shared.sendDeletion(ids)
    }
}

struct MatchRow: View {
    let record: MatchRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusBadge(status: record.status)
            }

            Text(setsText)
                .font(Theme.scoreFont(size: 17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(record.partnerName.isEmpty
                 ? record.startDate.relativeDayAndTime
                 : "\(record.startDate.relativeDayAndTime) · mit \(record.partnerName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var setsText: String {
        let sets = record.sets
        return sets.isEmpty ? "0:0" : sets.map(\.resultText).joined(separator: "  ")
    }
}

struct StatusBadge: View {
    let status: MatchStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(status.color.opacity(0.18), in: .capsule)
    }
}

extension Date {
    /// "Heute, 18:30" / "Gestern, 18:30" / "3. Nov., 18:30"
    var relativeDayAndTime: String {
        let time = formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Heute, \(time)" }
        if calendar.isDateInYesterday(self) { return "Gestern, \(time)" }
        return formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
