import PadelStats
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

            Section("Spieler") {
                NavigationLink {
                    NameEditorView(
                        title: "Gegner",
                        placeholder: "Gegner eintragen",
                        name: $record.opponentName,
                        suggestions: recentNames(\.opponentName),
                        onCommit: commitNames
                    )
                } label: {
                    PersonRow(role: "Gegner", name: record.opponentName, symbol: "person.2.fill", tint: Theme.opponent)
                }
                NavigationLink {
                    NameEditorView(
                        title: "Partner",
                        placeholder: "Partner eintragen",
                        name: $record.partnerName,
                        suggestions: recentNames(\.partnerName),
                        onCommit: commitNames
                    )
                } label: {
                    PersonRow(role: "Partner", name: record.partnerName, symbol: "person.fill", tint: Theme.me)
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
                let id = record.id
                modelContext.delete(record)
                try? modelContext.save()
                PhoneSync.shared.sendDeletion([id])
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

    /// Distinct names used in other matches (most recent first), for one-tap entry.
    func recentNames(_ keyPath: KeyPath<MatchRecord, String>) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for match in allMatches where match.id != record.id {
            let name = match[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
            if names.count == 8 { break }
        }
        return names
    }

    func commitNames() {
        try? modelContext.save()
        PhoneSync.shared.send([record.summary])
    }
}

/// "7:6" with the tiebreak points as a small superscript, like on a tennis scoreboard.
private struct SetResultText: View {
    let set: SetScore

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(set.resultText)
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

/// "Gegner  Max ›" row in the match details.
private struct PersonRow: View {
    let role: String
    let name: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(role)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(name.isEmpty ? "Eintragen" : name)
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
    }
}

/// Name entry for opponent or partner: system text input (dictation, Scribble, keyboard)
/// plus previously used names as one-tap suggestions.
struct NameEditorView: View {
    let title: String
    let placeholder: String
    @Binding var name: String
    let suggestions: [String]
    let onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                TextField(placeholder, text: $name)
                    .onSubmit(onCommit)
            } footer: {
                Text("Statt zu tippen: Diktat oder Scribble (Zeichnen) im Eingabe-Bildschirm wählen.")
            }

            if !suggestions.isEmpty {
                Section("Zuletzt") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            name = suggestion
                            onCommit()
                            dismiss()
                        } label: {
                            HStack {
                                Text(suggestion)
                                Spacer()
                                if suggestion.caseInsensitiveCompare(name) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.me)
                                }
                            }
                        }
                    }
                }
            }

            if !name.isEmpty {
                Section {
                    Button("Entfernen", role: .destructive) {
                        name = ""
                        onCommit()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
