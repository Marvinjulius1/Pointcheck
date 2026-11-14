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
    @State private var saved = 0

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
            FormScreen(title: "Ergebnis eintragen", subtitle: "Erst wir, dann die Gegner. Der Ball zeigt, wer den Satz hat.") {
                ScoreHero(sets: setScores, winner: winner)

                FormGroup(title: "Sätze") {
                    ForEach(Array($sets.enumerated()), id: \.element.id) { index, $set in
                        if index > 0 { RowDivider(inset: 16) }
                        SetEditor(index: index, set: $set) {
                            withAnimation(.snappy) { sets.removeAll { $0.id == set.id } }
                        }
                    }
                    if sets.count < 5 {
                        RowDivider(inset: 16)
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { sets.append(SetEntry()) }
                        } label: {
                            Label("Satz hinzufügen", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.pressScale)
                        .foregroundStyle(Theme.lime)
                    }
                }

                FormGroup(title: "Mitspieler", note: "Optional. Mit Konten verlinkst du die Spieler später im Match.") {
                    InputRow(label: "Partner", placeholder: "Name", text: $partner, symbol: "person.2.fill")
                    RowDivider()
                    InputRow(label: "Gegner", placeholder: "Name", text: $opponent, symbol: "person.fill.xmark")
                }

                FormGroup(title: "Wann") {
                    DateRow(title: "Gespielt am", date: $date, pastRange: ...Date.now)
                }

                if let errorText { FormError(text: errorText) }
            } footer: {
                FormActionBar(title: winner == nil ? "Ein Team muss gewinnen" : "Match speichern",
                              enabled: winner != nil && !setScores.isEmpty) { save() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .ballDrop(trigger: saved)
        }
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
        saved += 1
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            dismiss()
        }
    }
}

/// Big live preview of the result while typing.
struct ScoreHero: View {
    let sets: [SetScore]
    let winner: Team?

    var body: some View {
        let won = sets.filter { $0.winner == .me }.count
        let lost = sets.filter { $0.winner == .opponent }.count
        let tint: Color = winner == .me ? Theme.lime : winner == .opponent ? Theme.opponent : .secondary
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("\(won)").foregroundStyle(winner == .me ? Theme.lime : .primary)
                Text(":").foregroundStyle(.tertiary)
                Text("\(lost)").foregroundStyle(winner == .opponent ? Theme.opponent : .primary)
            }
            .font(Theme.scoreFont(size: 64))
            .contentTransition(.numericText())
            Text(winner == .me ? "Sieg" : winner == .opponent ? "Niederlage" : "Noch offen")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(winner == nil ? Color.secondary : Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(winner == nil ? Theme.surfaceRaised : tint, in: .capsule)
            if !sets.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                        Text(set.resultText)
                            .font(Theme.scoreFont(size: 17))
                            .foregroundStyle(set.winner == .me ? Theme.lime : Theme.opponent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.snappy, value: won + lost * 10)
    }
}

/// One set: two big numbers with ball buttons, tiebreak toggle, remove.
private struct SetEditor: View {
    let index: Int
    @Binding var set: ManualResultView.SetEntry
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(set.isMatchTiebreak ? "Match-Tiebreak" : "Satz \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.snappy) { set.isMatchTiebreak.toggle() }
                } label: {
                    Text("Tiebreak")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(set.isMatchTiebreak ? Theme.onAccent : .secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(set.isMatchTiebreak ? Theme.lime : Theme.surfaceRaised, in: .capsule)
                }
                .buttonStyle(.pressScale)
                if index > 0 {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Theme.surfaceRaised, in: .circle)
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel("Satz entfernen")
                }
            }
            HStack(spacing: 12) {
                ScoreDial(label: "Wir", value: $set.me, tint: Theme.lime, max: set.isMatchTiebreak ? 30 : 7,
                          leads: set.winner == .me)
                Text(":").font(Theme.scoreFont(size: 30)).foregroundStyle(.tertiary)
                ScoreDial(label: "Gegner", value: $set.opponent, tint: Theme.opponent, max: set.isMatchTiebreak ? 30 : 7,
                          leads: set.winner == .opponent)
            }
        }
        .padding(16)
    }
}

/// Number with − / + and a ball that sits by the leading team.
private struct ScoreDial: View {
    let label: String
    @Binding var value: Int
    let tint: Color
    let max: Int
    let leads: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.lime)
                    .opacity(leads ? 1 : 0)
                    .scaleEffect(leads ? 1 : 0.4)
            }
            HStack(spacing: 8) {
                dial("minus") { value = Swift.max(0, value - 1) }
                Text("\(value)")
                    .font(Theme.scoreFont(size: 34))
                    .foregroundStyle(leads ? tint : .primary)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                dial("plus") { value = Swift.min(max, value + 1) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
        .animation(.snappy, value: leads)
        .sensoryFeedback(.increase, trigger: value)
    }

    private func dial(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Theme.surfaceRaised, in: .circle)
        }
        .buttonStyle(.pressScale)
        .foregroundStyle(Color.primary)
    }
}
