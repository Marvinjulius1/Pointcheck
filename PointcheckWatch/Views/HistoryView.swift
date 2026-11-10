import SwiftData
import SwiftUI

/// All matches, newest first. Swipe left on a row to delete.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MatchRecord.startDate, order: .reverse) private var matches: [MatchRecord]

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
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(matches[index])
        }
        try? modelContext.save()
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

            Text(record.startDate.relativeDayAndTime)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var setsText: String {
        let sets = record.sets
        return sets.isEmpty ? "0:0" : sets.map(\.gamesText).joined(separator: "  ")
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
