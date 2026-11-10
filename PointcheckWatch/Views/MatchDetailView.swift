import PadelScoring
import SwiftData
import SwiftUI

/// Details of one match.
///
/// Opponent name: watchOS offers no API to force Scribble – `TextField` always opens the
/// system input screen (dictation, Scribble, keyboard). To avoid typing on the small
/// keyboard, previously used names are offered as one-tap suggestions.
struct MatchDetailView: View {
    @Bindable var record: MatchRecord
    @Query(sort: \MatchRecord.startDate, order: .reverse) private var allMatches: [MatchRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteDialog = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Text("\(record.setsWon.me)").foregroundStyle(Theme.me)
                        Text(":").foregroundStyle(.secondary)
                        Text("\(record.setsWon.opponent)").foregroundStyle(Theme.opponent)
                    }
                    .font(Theme.scoreFont(size: 34))
                    StatusBadge(status: record.status)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Namen eintragen", text: $record.opponentName)
                    .onSubmit { try? modelContext.save() }
            } header: {
                Text("Gegner")
            } footer: {
                Text("Tipp: Im Eingabe-Bildschirm kannst du statt der Tastatur Diktat oder Scribble (Zeichnen) nutzen.")
            }

            if !nameSuggestions.isEmpty {
                Section("Zuletzt gespielt gegen") {
                    ForEach(nameSuggestions, id: \.self) { name in
                        Button {
                            record.opponentName = name
                            try? modelContext.save()
                        } label: {
                            Label(name, systemImage: "person.2.fill")
                        }
                    }
                }
            }

            Section("Sätze") {
                if record.sets.isEmpty {
                    Text("Kein Spiel beendet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(record.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Satz \(index + 1)")
                            Spacer()
                            SetResultText(set: set)
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Datum", value: record.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Beginn", value: record.startDate.formatted(date: .omitted, time: .shortened))
                if let endDate = record.endDate {
                    LabeledContent("Dauer", value: Duration.seconds(endDate.timeIntervalSince(record.startDate))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
                LabeledContent("Modus", value: modeText)
                LabeledContent("40:40", value: record.goldenPoint ? "Golden Point" : "Vorteil")
            }

            Section {
                Button("Match löschen", role: .destructive) {
                    showsDeleteDialog = true
                }
            }
        }
        .navigationTitle(record.displayTitle)
        .confirmationDialog("Match löschen?", isPresented: $showsDeleteDialog, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                modelContext.delete(record)
                try? modelContext.save()
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

extension MatchDetailView {
    var modeText: String {
        let sets = record.bestOf == 1 ? "1 Satz" : "Best of \(record.bestOf)"
        return record.superTiebreak && record.bestOf > 1 ? "\(sets), Match-Tiebreak" : sets
    }

    /// Distinct opponent names from other matches, most recent first.
    var nameSuggestions: [String] {
        let current = record.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var names: [String] = []
        for match in allMatches where match.id != record.id {
            let name = match.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()
            guard !name.isEmpty, name.caseInsensitiveCompare(current) != .orderedSame,
                  seen.insert(key).inserted else { continue }
            names.append(name)
            if names.count == 6 { break }
        }
        return names
    }
}

/// "7:6" with the tiebreak points as a small superscript, like on a tennis scoreboard.
private struct SetResultText: View {
    let set: SetScore

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(set.gamesText)
                .font(Theme.scoreFont(size: 17))
                .foregroundStyle(color)
            if let tiebreak = set.tiebreakText {
                Text(tiebreak)
                    .font(Theme.scoreFont(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch set.winner {
        case .me: Theme.me
        case .opponent: Theme.opponent
        case nil: .primary
        }
    }
}
