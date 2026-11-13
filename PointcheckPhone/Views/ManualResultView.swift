import PadelStats
import SwiftUI

/// Enter a finished match by hand: sets, date, names. For players without a watch.
struct ManualResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date.now
    @State private var sets: [SetEntry] = [SetEntry(), SetEntry()]
    @State private var partner = ""
    @State private var opponent = ""
    @State private var errorText: String?

    struct SetEntry: Identifiable {
        let id = UUID()
        var me = 6
        var opponent = 4
        var isMatchTiebreak = false

        var winner: Team? {
            if me == opponent { return nil }
            return me > opponent ? .me : .opponent
        }

        var setScore: SetScore? {
            guard let winner else { return nil }
            if isMatchTiebreak {
                return SetScore(games: TeamScore(me: winner == .me ? 1 : 0, opponent: winner == .me ? 0 : 1),
                                tiebreak: TeamScore(me: me, opponent: opponent), isSuperTiebreak: true)
            }
            return SetScore(games: TeamScore(me: me, opponent: opponent))
        }
    }

    private var setScores: [SetScore] { sets.compactMap(\.setScore) }
    private var winner: Team? {
        let won = setScores.filter { $0.winner == .me }.count
        let lost = setScores.filter { $0.winner == .opponent }.count
        if won == lost { return nil }
        return won > lost ? .me : .opponent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        if let winner {
                            Text(winner == .me ? "Sieg" : "Niederlage")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(winner == .me ? Theme.me : Theme.opponent)
                        } else {
                            Text("Unentschieden geht nicht").font(.headline).foregroundStyle(.secondary)
                        }
                        Text(setScores.map(\.resultText).joined(separator: "  "))
                            .font(Theme.scoreFont(size: 22))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach($sets) { $set in
                        VStack(spacing: 10) {
                            HStack {
                                Text(set.isMatchTiebreak ? "Match-Tiebreak" : "Satz \((sets.firstIndex { $0.id == set.id } ?? 0) + 1)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Toggle("Match-Tiebreak", isOn: $set.isMatchTiebreak)
                                    .labelsHidden()
                                    .controlSize(.mini)
                                Text("Tiebreak").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                scoreStepper("Wir", value: $set.me, tint: Theme.me, max: set.isMatchTiebreak ? 30 : 7)
                                Text(":").font(Theme.scoreFont(size: 28)).foregroundStyle(.secondary)
                                scoreStepper("Gegner", value: $set.opponent, tint: Theme.opponent, max: set.isMatchTiebreak ? 30 : 7)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { sets.remove(atOffsets: $0) }
                    if sets.count < 5 {
                        Button("Satz hinzufügen", systemImage: "plus") {
                            sets.append(SetEntry(me: 6, opponent: 4, isMatchTiebreak: false))
                        }
                    }
                } header: {
                    Text("Sätze")
                } footer: {
                    Text("Satz von links nach rechts: erst wir, dann die Gegner. Für einen Match-Tiebreak den Schalter umlegen und die Punkte eintragen (z. B. 10:8).")
                }

                Section("Spieler (optional)") {
                    TextField("Partner", text: $partner)
                    TextField("Gegner", text: $opponent)
                }

                Section {
                    DatePicker("Gespielt am", selection: $date, in: ...Date.now)
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.opponent) }
                }
            }
            .navigationTitle("Ergebnis eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(winner == nil || setScores.isEmpty)
                }
            }
        }
    }

    private func scoreStepper(_ label: String, value: Binding<Int>, tint: Color, max: Int) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { value.wrappedValue = Swift.max(0, value.wrappedValue - 1) } label: {
                    Image(systemName: "minus").frame(width: 32, height: 32).background(Theme.surface, in: .circle)
                }
                .buttonStyle(.plain)
                Text("\(value.wrappedValue)")
                    .font(Theme.scoreFont(size: 28))
                    .foregroundStyle(tint)
                    .frame(minWidth: 36)
                    .contentTransition(.numericText())
                Button { value.wrappedValue = Swift.min(max, value.wrappedValue + 1) } label: {
                    Image(systemName: "plus").frame(width: 32, height: 32).background(Theme.surface, in: .circle)
                }
                .buttonStyle(.plain)
            }
            .animation(.snappy, value: value.wrappedValue)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        guard let winner else { return }
        let summary = MatchSummary(
            startDate: date,
            endDate: date.addingTimeInterval(75 * 60),
            opponentName: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
            partnerName: partner.trimmingCharacters(in: .whitespacesAndNewlines),
            sets: setScores,
            winner: winner,
            isCompleted: true,
            bestOf: setScores.count.isMultiple(of: 2) ? setScores.count + 1 : setScores.count,
            goldenPoint: false,
            superTiebreak: setScores.contains { $0.isSuperTiebreak }
        )
        MatchStore(context: modelContext).upsert([summary])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
